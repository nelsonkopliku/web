# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Schedule do
  @moduledoc """
  The operation schedule aggregate.

  It decides when the operation of a schedule runs: the first occurrence at
  creation or change, from the time the change was requested. The aggregate
  never reads the clock: the commands carry the time.

  The operation policies are not checked here: they read the current state of
  the target, so they run outside the aggregate, when the schedule is saved and
  when it runs.
  """

  @required_fields []

  use Trento.Support.Type

  alias Trento.Operations.Commands.{ChangeOperationSchedule, ScheduleOperation}
  alias Trento.Operations.Events.{OperationScheduleChanged, OperationScheduled}
  alias Trento.Operations.ValueObjects.{OperationParams, Recurrence}
  alias Trento.Scheduling.Recurrence, as: Occurrences

  deftype do
    field :schedule_id, Ecto.UUID
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :operation, :string
    embeds_one :params, OperationParams
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    embeds_one :recurrence, Recurrence
    field :next_run_at, :utc_datetime_usec
    field :occurrences, :integer, default: 0
    field :bulk_id, Ecto.UUID
  end

  def execute(%__MODULE__{schedule_id: nil}, %ScheduleOperation{} = command) do
    with :ok <- starts_in_the_future(command.starts_at, command.requested_at),
         {:ok, next_run_at} <-
           first_occurrence(
             command.recurrence,
             command.starts_at,
             command.timezone,
             command.requested_at
           ) do
      %OperationScheduled{
        schedule_id: command.schedule_id,
        target_type: command.target_type,
        target_id: command.target_id,
        operation: command.operation,
        params: command.params,
        starts_at: command.starts_at,
        timezone: command.timezone,
        recurrence: command.recurrence,
        next_run_at: next_run_at,
        bulk_id: command.bulk_id
      }
    end
  end

  def execute(%__MODULE__{}, %ScheduleOperation{}),
    do: {:error, :operation_schedule_already_exists}

  def execute(%__MODULE__{schedule_id: nil}, _), do: {:error, :operation_schedule_not_found}

  # An ongoing periodic schedule can keep its start: it continues with its
  # next occurrence, never with one in the past.
  def execute(%__MODULE__{} = schedule, %ChangeOperationSchedule{} = command) do
    with :ok <- starts_in_the_future(schedule.starts_at, command.starts_at, command.requested_at),
         {:ok, next_run_at} <-
           first_occurrence(
             command.recurrence,
             command.starts_at,
             command.timezone,
             command.requested_at
           ) do
      %OperationScheduleChanged{
        schedule_id: schedule.schedule_id,
        params: command.params,
        starts_at: command.starts_at,
        timezone: command.timezone,
        recurrence: command.recurrence,
        next_run_at: next_run_at
      }
    end
  end

  def apply(%__MODULE__{} = schedule, %OperationScheduled{} = event) do
    %__MODULE__{
      schedule
      | schedule_id: event.schedule_id,
        target_type: event.target_type,
        target_id: event.target_id,
        operation: event.operation,
        params: event.params,
        starts_at: event.starts_at,
        timezone: event.timezone,
        recurrence: event.recurrence,
        next_run_at: event.next_run_at,
        occurrences: 0,
        bulk_id: event.bulk_id
    }
  end

  def apply(%__MODULE__{} = schedule, %OperationScheduleChanged{} = event) do
    %__MODULE__{
      schedule
      | params: event.params,
        starts_at: event.starts_at,
        timezone: event.timezone,
        recurrence: event.recurrence,
        next_run_at: event.next_run_at,
        occurrences: 0
    }
  end

  # A start that does not change can be in the past
  defp starts_in_the_future(current, starts_at, requested_at) do
    if DateTime.compare(current, starts_at) == :eq,
      do: :ok,
      else: starts_in_the_future(starts_at, requested_at)
  end

  defp starts_in_the_future(starts_at, requested_at) do
    if DateTime.compare(starts_at, requested_at) == :lt,
      do: {:error, :operation_schedule_start_in_the_past},
      else: :ok
  end

  # The first occurrence from the start, and not before the request.
  defp first_occurrence(recurrence, starts_at, timezone, requested_at) do
    from = [starts_at, requested_at] |> Enum.max(DateTime) |> DateTime.add(-1, :microsecond)

    recurrence
    |> Recurrence.to_rule(starts_at, timezone, 0)
    |> Occurrences.next_occurrence(from)
    |> case do
      nil when is_nil(recurrence) -> {:error, :operation_schedule_start_in_the_past}
      nil -> {:error, :operation_schedule_without_occurrences}
      first -> {:ok, first}
    end
  end
end
