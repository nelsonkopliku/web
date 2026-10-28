# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows do
  @moduledoc """
  Maintenance windows (TRNT-4774): one-time or periodic time slots in which
  Trento does not execute checks, or does not run operations, on a target
  and on the targets it covers.

  Event sourced: every change is a command to a
  `Trento.MaintenanceWindows.MaintenanceWindow` aggregate, and the reads come
  from the maintenance_windows read model. A change waits until the read
  model shows it, so that the answer and the next read show the change. When
  the read model takes too long, the change is saved anyway: it is logged,
  and `{:error, :consistency_timeout}` tells that the read model does not
  show it yet.
  """

  import Ecto.Query, only: [from: 2]

  alias Trento.Clusters.Projections.ClusterReadModel
  alias Trento.Databases.Projections.DatabaseReadModel
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.MaintenanceWindows.Commands.ScheduleMaintenanceWindow

  alias Trento.MaintenanceWindows.Projections.{
    MaintenanceWindowProjector,
    MaintenanceWindowReadModel
  }

  alias Trento.MaintenanceWindows.WindowActivity
  alias Trento.Repo
  alias Trento.SapSystems.Projections.SapSystemReadModel
  alias Trento.Support.{CommandedUtils, DateService}

  require Logger

  @doc """
  Sets a maintenance window on a registered target.
  """
  @spec create_window(map(), String.t(), module()) ::
          {:ok, MaintenanceWindowReadModel.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
          | {:error, :consistency_timeout}
          | {:error, any()}
  def create_window(attrs, actor, date_service \\ DateService) do
    changeset = schedule_changeset(attrs, UUID.uuid4(), date_service.utc_now())

    with {:ok, command} <- Ecto.Changeset.apply_action(changeset, :insert),
         :ok <- registered(command.target_type, command.target_id) do
      command
      |> dispatch(metadata: %{"created_by" => actor})
      |> saved(changeset, command.window_id, fn window ->
        WindowActivity.record(
          :maintenance_window_scheduled,
          window || provisional(command),
          actor
        )
      end)
    end
  end

  @doc """
  Tells whether a target is registered: a window can only be set on one.
  """
  @spec registered(String.t(), String.t()) :: :ok | {:error, :not_found}
  def registered(target_type, target_id) do
    query =
      from t in read_model(target_type),
        where: t.id == ^target_id and is_nil(t.deregistered_at),
        select: true

    if Repo.exists?(query), do: :ok, else: {:error, :not_found}
  end

  defp read_model("host"), do: HostReadModel
  defp read_model("cluster"), do: ClusterReadModel
  defp read_model("database"), do: DatabaseReadModel
  defp read_model("sap_system"), do: SapSystemReadModel

  defp schedule_changeset(attrs, window_id, requested_at) do
    ScheduleMaintenanceWindow.changeset(
      %ScheduleMaintenanceWindow{},
      Map.merge(attrs, %{window_id: window_id, requested_at: requested_at})
    )
  end

  # Waits for the read model of the windows, see the moduledoc.
  defp dispatch(command, opts) do
    CommandedUtils.correlated_dispatch(
      command,
      [consistency: [MaintenanceWindowProjector]] ++ opts
    )
  end

  # A command that went through is logged, even when the read model is late.
  # The aggregate refuses a window that starts in the past or is over: the
  # error is told on the start.
  defp saved(:ok, _changeset, window_id, log) do
    window = Repo.get!(MaintenanceWindowReadModel, window_id)
    log.(window)
    {:ok, window}
  end

  defp saved({:error, :consistency_timeout}, _changeset, window_id, log) do
    Logger.warning("Maintenance window #{window_id} saved, its read model is not up to date")
    log.(nil)
    {:error, :consistency_timeout}
  end

  defp saved({:error, :maintenance_window_start_in_the_past}, changeset, _, _),
    do: {:error, Ecto.Changeset.add_error(changeset, :starts_at, "is in the past")}

  defp saved({:error, :maintenance_window_over}, changeset, _, _),
    do:
      {:error,
       Ecto.Changeset.add_error(changeset, :starts_at, "leaves no occurrence that is not over")}

  defp saved({:error, _} = error, _, _, _), do: error

  # The window as the read model will show it, to log a change that the read
  # model does not show yet.
  defp provisional(%ScheduleMaintenanceWindow{} = command) do
    recurrence = command.recurrence

    %MaintenanceWindowReadModel{
      id: command.window_id,
      target_type: command.target_type,
      target_id: command.target_id,
      starts_at: command.starts_at,
      timezone: command.timezone,
      duration_minutes: command.duration_minutes,
      frequency: recurrence && Atom.to_string(recurrence.frequency),
      interval: (recurrence && recurrence.interval) || 1,
      weekdays: (recurrence && recurrence.weekdays) || [],
      ends_on: recurrence && recurrence.ends_on,
      forbid_checks_execution: :checks_execution in command.forbids,
      forbid_operations: :operations in command.forbids,
      bulk_id: command.bulk_id
    }
  end
end
