# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling do
  @moduledoc """
  Periodic checks executions of hosts and clusters.

  A target uses its own interval, kept on the Host and Cluster aggregates and
  projected into the target_checks_intervals read model, or the global one of
  `Trento.Settings.get_checks_execution_settings/0`.
  """

  import Ecto.Query, only: [from: 2]

  alias Trento.ChecksScheduling.{ExecutionRequest, Interval}

  alias Trento.ChecksScheduling.Projections.{
    TargetChecksIntervalProjector,
    TargetChecksIntervalReadModel
  }

  alias Trento.Clusters
  alias Trento.Clusters.Commands.ChangeClusterChecksInterval
  alias Trento.Clusters.Projections.ClusterReadModel
  alias Trento.Hosts
  alias Trento.Hosts.Commands.ChangeHostChecksInterval
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.Repo
  alias Trento.Settings
  alias Trento.Support.{CommandedUtils, DateService}

  require Logger

  @type target_type :: :host | :cluster

  @due_tolerance_seconds 30

  @spec get_target_schedule(target_type(), String.t(), module()) ::
          {:ok, map()} | {:error, :not_found}
  def get_target_schedule(target_type, target_id, date_service \\ DateService) do
    with :ok <- target_exists(target_type, target_id) do
      {:ok, view(interval(target_id), target_id, date_service.utc_now())}
    end
  end

  @doc """
  Replaces the interval of a target. A nil interval means the global one.

  The change waits until the read model shows it, so that the next read shows
  it too. When the read model takes too long, the change is saved anyway.
  """
  @spec update_target_schedule(target_type(), String.t(), map(), module()) ::
          {:ok, map()} | {:error, :not_found} | {:error, Ecto.Changeset.t()} | {:error, any()}
  def update_target_schedule(
        target_type,
        target_id,
        %{interval: interval},
        date_service \\ DateService
      ) do
    with :ok <- target_exists(target_type, target_id),
         {:ok, command} <- command(target_type, target_id, interval),
         :ok <- dispatch(command, target_id) do
      {:ok, view(interval, target_id, date_service.utc_now())}
    end
  end

  @doc """
  Removes the last periodic request of a target, when it is deregistered.
  """
  @spec delete_execution_request(String.t()) :: :ok
  def delete_execution_request(target_id) do
    Repo.delete_all(from r in ExecutionRequest, where: r.target_id == ^target_id)
    :ok
  end

  @doc """
  Requests a checks execution for every host and checkable cluster with
  selected checks whose interval elapsed. A Quantum job calls it every
  minute. The settings, the intervals and the last requests are read once
  per run.

  When the previous execution of a target still runs, Wanda refuses the new
  request: executions do not pile up. A request that fails is logged and
  retried at the next run.
  """
  @spec request_due_executions(module()) :: :ok
  def request_due_executions(date_service \\ DateService) do
    now = date_service.utc_now()
    global_interval = Settings.get_checks_execution_settings().interval
    intervals = Map.new(Repo.all(TargetChecksIntervalReadModel), &{&1.target_id, &1.interval})
    last_requests = Map.new(Repo.all(ExecutionRequest), &{&1.target_id, &1.last_requested_at})

    for {target_type, target_id} <- targets_with_checks(),
        interval = effective_interval(Map.get(intervals, target_id), global_interval),
        due?(interval, Map.get(last_requests, target_id), now) do
      request(target_type, target_id, now)
    end

    :ok
  end

  @doc """
  The interval that applies to a target with the given own interval.
  """
  @spec effective_interval(Interval.t() | nil, Interval.t()) :: Interval.t()
  def effective_interval(nil, global_interval), do: global_interval
  def effective_interval(interval, _), do: interval

  @doc """
  When the next periodic execution runs, nil when they are disabled.
  """
  @spec next_execution_at(Interval.t(), DateTime.t() | nil, DateTime.t()) :: DateTime.t() | nil
  def next_execution_at(effective_interval, last_requested_at, now) do
    case {Interval.to_minutes(effective_interval), last_requested_at} do
      {nil, _} -> nil
      {_, nil} -> now
      {minutes, last} -> Enum.max([DateTime.add(last, minutes, :minute), now], DateTime)
    end
  end

  # The job runs every minute, a few seconds later or earlier each time: an
  # execution is due once its interval elapsed, give or take half a minute, so
  # that a 5 minutes interval does not become 6.
  defp due?(interval, last_requested_at, now) do
    case Interval.to_minutes(interval) do
      nil ->
        false

      minutes ->
        is_nil(last_requested_at) or
          DateTime.diff(now, last_requested_at) >= minutes * 60 - @due_tolerance_seconds
    end
  end

  defp request(target_type, target_id, now) do
    case request_execution(target_type, target_id) do
      :ok ->
        Repo.insert!(
          %ExecutionRequest{
            target_id: target_id,
            target_type: Atom.to_string(target_type),
            last_requested_at: now
          },
          on_conflict: [set: [last_requested_at: now, updated_at: now]],
          conflict_target: :target_id
        )

      {:error, reason} ->
        Logger.warning(
          "Could not request the checks execution of #{target_type} #{target_id}, retrying at the next run: #{inspect(reason)}"
        )
    end
  end

  defp request_execution(:host, host_id), do: Hosts.request_checks_execution(host_id)
  defp request_execution(:cluster, cluster_id), do: Clusters.request_checks_execution(cluster_id)

  defp targets_with_checks do
    hosts =
      Repo.all(
        from h in HostReadModel,
          where: is_nil(h.deregistered_at) and fragment("cardinality(?) > 0", h.selected_checks),
          select: h.id
      )

    clusters =
      Repo.all(
        from c in ClusterReadModel,
          where:
            is_nil(c.deregistered_at) and c.type in ^Clusters.checkable_cluster_types() and
              fragment("cardinality(?) > 0", c.selected_checks),
          select: c.id
      )

    Enum.map(hosts, &{:host, &1}) ++ Enum.map(clusters, &{:cluster, &1})
  end

  defp view(interval, target_id, now) do
    global_interval = Settings.get_checks_execution_settings().interval
    effective_interval = effective_interval(interval, global_interval)
    last_requested_at = last_requested_at(target_id)

    %{
      interval: interval,
      effective_interval: effective_interval,
      global_interval: global_interval,
      last_requested_at: last_requested_at,
      next_execution_at: next_execution_at(effective_interval, last_requested_at, now)
    }
  end

  defp interval(target_id) do
    case Repo.get(TargetChecksIntervalReadModel, target_id) do
      nil -> nil
      %TargetChecksIntervalReadModel{interval: interval} -> interval
    end
  end

  defp last_requested_at(target_id) do
    case Repo.get(ExecutionRequest, target_id) do
      nil -> nil
      %ExecutionRequest{last_requested_at: last_requested_at} -> last_requested_at
    end
  end

  defp command(:host, host_id, interval),
    do: new(ChangeHostChecksInterval, %{host_id: host_id, interval: interval})

  defp command(:cluster, cluster_id, interval),
    do: new(ChangeClusterChecksInterval, %{cluster_id: cluster_id, interval: interval})

  defp new(command, attrs) do
    command
    |> struct()
    |> command.changeset(attrs)
    |> Ecto.Changeset.apply_action(:update)
  end

  defp dispatch(command, target_id) do
    case CommandedUtils.correlated_dispatch(command, consistency: [TargetChecksIntervalProjector]) do
      :ok ->
        :ok

      {:error, :consistency_timeout} ->
        Logger.warning("Checks execution interval of #{target_id} saved, its read model is late")

      {:error, reason} when reason in [:host_not_registered, :cluster_not_registered] ->
        {:error, :not_found}

      {:error, _} = error ->
        error
    end
  end

  defp target_exists(:host, host_id), do: registered(Repo.get(HostReadModel, host_id))
  defp target_exists(:cluster, cluster_id), do: registered(Repo.get(ClusterReadModel, cluster_id))

  defp registered(%{deregistered_at: nil}), do: :ok
  defp registered(_), do: {:error, :not_found}
end
