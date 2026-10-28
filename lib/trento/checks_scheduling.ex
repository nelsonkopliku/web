# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling do
  @moduledoc """
  Periodic checks executions of hosts and clusters.

  A target uses its own interval, or the global one of
  `Trento.Settings.get_checks_execution_settings/0`.
  """

  import Ecto.Query, only: [from: 2]

  alias Trento.ChecksScheduling.{Interval, TargetSchedule}
  alias Trento.Clusters.Projections.ClusterReadModel
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.Repo
  alias Trento.Settings
  alias Trento.Support.DateService

  @type target_type :: :host | :cluster

  @spec get_target_schedule(target_type(), String.t(), module()) ::
          {:ok, map()} | {:error, :not_found}
  def get_target_schedule(target_type, target_id, date_service \\ DateService) do
    with :ok <- target_exists(target_type, target_id) do
      {:ok, view(load(target_type, target_id), date_service.utc_now())}
    end
  end

  @spec update_target_schedule(target_type(), String.t(), map(), module()) ::
          {:ok, map()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_target_schedule(target_type, target_id, attrs, date_service \\ DateService) do
    now = date_service.utc_now()

    with :ok <- target_exists(target_type, target_id),
         {:ok, schedule} <-
           target_type
           |> load(target_id)
           |> TargetSchedule.changeset(attrs)
           |> Repo.insert_or_update() do
      {:ok, view(schedule, now)}
    end
  end

  @doc """
  Removes the checks execution settings of a target, when it is deregistered.
  """
  @spec delete_target_schedule(String.t()) :: :ok
  def delete_target_schedule(target_id) do
    Repo.delete_all(from s in TargetSchedule, where: s.target_id == ^target_id)
    :ok
  end

  @doc """
  The interval that applies to the target.
  """
  @spec effective_interval(TargetSchedule.t()) :: Interval.t()
  def effective_interval(%TargetSchedule{interval: nil}),
    do: Settings.get_checks_execution_settings().interval

  def effective_interval(%TargetSchedule{interval: interval}), do: interval

  @doc """
  When the next periodic execution runs, nil when they are disabled.
  """
  @spec next_execution_at(TargetSchedule.t(), DateTime.t()) :: DateTime.t() | nil
  def next_execution_at(%TargetSchedule{} = schedule, now) do
    case Interval.to_minutes(effective_interval(schedule)) do
      nil ->
        nil

      minutes ->
        case schedule.last_requested_at do
          nil -> now
          last -> Enum.max([DateTime.add(last, minutes, :minute), now], DateTime)
        end
    end
  end

  defp view(%TargetSchedule{} = schedule, now) do
    %{
      interval: schedule.interval,
      effective_interval: effective_interval(schedule),
      global_interval: Settings.get_checks_execution_settings().interval,
      last_requested_at: schedule.last_requested_at,
      next_execution_at: next_execution_at(schedule, now)
    }
  end

  defp load(target_type, target_id) do
    Repo.get(TargetSchedule, target_id) ||
      %TargetSchedule{target_id: target_id, target_type: Atom.to_string(target_type)}
  end

  defp target_exists(:host, host_id), do: registered(Repo.get(HostReadModel, host_id))
  defp target_exists(:cluster, cluster_id), do: registered(Repo.get(ClusterReadModel, cluster_id))

  defp registered(%{deregistered_at: nil}), do: :ok
  defp registered(_), do: {:error, :not_found}
end
