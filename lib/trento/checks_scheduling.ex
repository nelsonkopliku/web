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

  alias Trento.Clusters.Commands.ChangeClusterChecksInterval
  alias Trento.Clusters.Projections.ClusterReadModel
  alias Trento.Hosts.Commands.ChangeHostChecksInterval
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.Repo
  alias Trento.Settings
  alias Trento.Support.{CommandedUtils, DateService}

  require Logger

  @type target_type :: :host | :cluster

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
