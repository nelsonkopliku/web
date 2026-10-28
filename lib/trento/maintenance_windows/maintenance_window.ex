# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.MaintenanceWindow do
  @moduledoc """
  The maintenance window aggregate: a one-time or periodic time slot, set on
  a host, cluster, database or SAP system, which forbids checks executions,
  operations, or both on the targets it covers.

  It decides whether the timing of a window holds when it is set: the window
  starts after the request and has an occurrence that is not over. The
  aggregate never reads the clock: the commands carry the time. Which
  targets a window covers is resolved when it is asked, on the topology the
  read models know, see `Trento.MaintenanceWindows.Coverage`.
  """

  @required_fields []

  use Trento.Support.Type

  require Trento.MaintenanceWindows.Enums.ForbiddenAction, as: ForbiddenAction

  alias Trento.MaintenanceWindows.Commands.ScheduleMaintenanceWindow
  alias Trento.MaintenanceWindows.Events.MaintenanceWindowScheduled
  alias Trento.MaintenanceWindows.ValueObjects.Recurrence
  alias Trento.Scheduling.Recurrence, as: Occurrences

  deftype do
    field :window_id, Ecto.UUID
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    field :duration_minutes, :integer
    embeds_one :recurrence, Recurrence
    field :forbids, {:array, Ecto.Enum}, values: ForbiddenAction.values()
    field :bulk_id, Ecto.UUID
  end

  def execute(%__MODULE__{window_id: nil}, %ScheduleMaintenanceWindow{} = command) do
    with :ok <- starts_in_the_future(command.starts_at, command.requested_at),
         :ok <- not_over(command, command.requested_at) do
      %MaintenanceWindowScheduled{
        window_id: command.window_id,
        target_type: command.target_type,
        target_id: command.target_id,
        starts_at: command.starts_at,
        timezone: command.timezone,
        duration_minutes: command.duration_minutes,
        recurrence: command.recurrence,
        forbids: command.forbids,
        bulk_id: command.bulk_id
      }
    end
  end

  def execute(%__MODULE__{}, %ScheduleMaintenanceWindow{}),
    do: {:error, :maintenance_window_already_exists}

  def apply(%__MODULE__{} = window, %MaintenanceWindowScheduled{} = event) do
    %__MODULE__{
      window
      | window_id: event.window_id,
        target_type: event.target_type,
        target_id: event.target_id,
        starts_at: event.starts_at,
        timezone: event.timezone,
        duration_minutes: event.duration_minutes,
        recurrence: event.recurrence,
        forbids: event.forbids,
        bulk_id: event.bulk_id
    }
  end

  defp starts_in_the_future(starts_at, requested_at) do
    if DateTime.compare(starts_at, requested_at) == :lt,
      do: {:error, :maintenance_window_start_in_the_past},
      else: :ok
  end

  # A window must have an occurrence that is not over yet.
  defp not_over(%{starts_at: starts_at, duration_minutes: duration} = timing, now) do
    from =
      Enum.max(
        [DateTime.add(now, -duration, :minute), DateTime.add(starts_at, -1, :microsecond)],
        DateTime
      )

    timing.recurrence
    |> Recurrence.to_rule(starts_at, timing.timezone)
    |> Occurrences.next_occurrence(from)
    |> case do
      nil -> {:error, :maintenance_window_over}
      _ -> :ok
    end
  end
end
