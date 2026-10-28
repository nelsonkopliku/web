# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Schedule do
  @moduledoc """
  The operation schedule aggregate.

  It decides when the operation of a schedule runs: the first occurrence at
  creation or change, from the time the change was requested, and the next
  one after each run. The aggregate never reads the clock: the commands carry
  the time.

  The operation policies are not checked here: they read the current state of
  the target, so they run outside the aggregate, when the schedule is saved and
  when it runs.

  Runs:

  - a due occurrence starts a run, which names the operation id to request,
    derived from the schedule and the occurrence; an event handler requests
    the operation and records the outcome
  - a run whose outcome is not recorded starts again when it is triggered
    again, with the same operation id; later than the grace period after the
    occurrence, the occurrence fails because Trento was not available
  - after the outcome, a one-time schedule ends, and a periodic one moves to
    its next occurrence after the outcome; the occurrences missed meanwhile
    count, and are not caught up
  - the outcome of a run that started before a change or a cancellation is
    recorded, without moving the schedule
  """

  @required_fields []

  use Trento.Support.Type

  alias Trento.Operations.Commands.{
    CancelOperationSchedule,
    ChangeOperationSchedule,
    CompleteScheduledRun,
    ScheduleOperation,
    TriggerScheduledRun
  }

  alias Trento.Operations.Events.{
    OperationScheduleCancelled,
    OperationScheduleChanged,
    OperationScheduled,
    ScheduledOperationRequested,
    ScheduledOperationRequestFailed,
    ScheduledRunStarted
  }

  alias Trento.Operations.ValueObjects.{OperationParams, PendingRun, Recurrence}
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
    field :cancelled, :boolean, default: false
    embeds_one :pending_run, PendingRun
  end

  @grace_period_seconds 300
  @restart_after_seconds 30

  @doc """
  How late an occurrence can still run.
  """
  @spec grace_period_seconds() :: pos_integer()
  def grace_period_seconds, do: @grace_period_seconds

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

  def execute(%__MODULE__{pending_run: pending_run} = schedule, %CompleteScheduledRun{} = command) do
    if run_of?(pending_run, command.run_at),
      do: complete(schedule, command),
      else: {:error, :operation_schedule_stale_run}
  end

  def execute(%__MODULE__{cancelled: true}, _), do: {:error, :operation_schedule_not_found}
  def execute(%__MODULE__{next_run_at: nil}, _), do: {:error, :operation_schedule_not_found}

  def execute(%__MODULE__{next_run_at: next_run_at} = schedule, %TriggerScheduledRun{} = command) do
    cond do
      DateTime.compare(command.run_at, next_run_at) != :eq ->
        {:error, :operation_schedule_stale_run}

      late?(command.run_at, command.triggered_at) ->
        not_available(schedule, command)

      pending?(schedule, command) ->
        {:error, :operation_schedule_run_pending}

      true ->
        start(schedule, command)
    end
  end

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

  def execute(%__MODULE__{schedule_id: schedule_id}, %CancelOperationSchedule{}),
    do: %OperationScheduleCancelled{schedule_id: schedule_id}

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

  def apply(%__MODULE__{} = schedule, %OperationScheduleCancelled{}),
    do: %__MODULE__{schedule | cancelled: true}

  def apply(%__MODULE__{} = schedule, %ScheduledRunStarted{} = event) do
    %__MODULE__{
      schedule
      | pending_run: %PendingRun{
          run_at: event.run_at,
          operation_id: event.operation_id,
          params: event.params,
          started_at: event.started_at
        }
    }
  end

  def apply(%__MODULE__{} = schedule, %event{} = outcome)
      when event in [ScheduledOperationRequested, ScheduledOperationRequestFailed] do
    %__MODULE__{
      schedule
      | next_run_at: outcome.next_run_at,
        occurrences: outcome.occurrences,
        pending_run: settle(schedule.pending_run, outcome.run_at)
    }
  end

  defp start(%__MODULE__{} = schedule, %TriggerScheduledRun{run_at: run_at} = command) do
    %ScheduledRunStarted{
      schedule_id: schedule.schedule_id,
      run_at: run_at,
      operation_id: operation_id(schedule.schedule_id, run_at),
      target_type: schedule.target_type,
      target_id: schedule.target_id,
      operation: schedule.operation,
      params: schedule.params,
      started_at: command.triggered_at
    }
  end

  defp not_available(%__MODULE__{} = schedule, %TriggerScheduledRun{run_at: run_at} = command) do
    {occurrences, next_run_at} = advance(schedule, run_at, command.triggered_at)

    %ScheduledOperationRequestFailed{
      schedule_id: schedule.schedule_id,
      run_at: run_at,
      reason: :not_available,
      errors: [],
      occurrences: occurrences,
      next_run_at: next_run_at
    }
  end

  defp complete(
         %__MODULE__{pending_run: pending_run} = schedule,
         %CompleteScheduledRun{} = command
       ) do
    {occurrences, next_run_at} = after_run(schedule, command)

    case command.outcome do
      :requested ->
        %ScheduledOperationRequested{
          schedule_id: schedule.schedule_id,
          run_at: command.run_at,
          operation_id: pending_run.operation_id,
          target_type: schedule.target_type,
          target_id: schedule.target_id,
          operation: schedule.operation,
          params: pending_run.params,
          occurrences: occurrences,
          next_run_at: next_run_at
        }

      :failed ->
        %ScheduledOperationRequestFailed{
          schedule_id: schedule.schedule_id,
          run_at: command.run_at,
          reason: command.reason,
          errors: command.errors,
          occurrences: occurrences,
          next_run_at: next_run_at
        }
    end
  end

  # The schedule moves on when the run is the one of its next occurrence. A
  # change or a cancellation during the run already decided what comes next.
  defp after_run(%__MODULE__{cancelled: true, occurrences: occurrences}, _),
    do: {occurrences, nil}

  defp after_run(
         %__MODULE__{next_run_at: next_run_at} = schedule,
         %CompleteScheduledRun{} = command
       ) do
    if DateTime.compare(command.run_at, next_run_at) == :eq,
      do: advance(schedule, command.run_at, command.completed_at),
      else: {schedule.occurrences, next_run_at}
  end

  # The handled occurrence counts, and so does every occurrence missed until
  # now: they are not caught up.
  defp advance(%__MODULE__{occurrences: occurrences} = schedule, run_at, now),
    do: next_occurrence(schedule, occurrences + 1, run_at, now)

  defp next_occurrence(%__MODULE__{} = schedule, done, after_instant, now) do
    schedule.recurrence
    |> Recurrence.to_rule(schedule.starts_at, schedule.timezone, done)
    |> Occurrences.next_occurrence(after_instant)
    |> case do
      nil ->
        {done, nil}

      next ->
        if DateTime.compare(next, now) == :gt,
          do: {done, next},
          else: next_occurrence(schedule, done + 1, next, now)
    end
  end

  defp late?(run_at, now), do: DateTime.diff(now, run_at) > @grace_period_seconds

  # A run that started a moment ago is still requesting its operation
  defp pending?(%__MODULE__{pending_run: pending_run}, %TriggerScheduledRun{} = command) do
    run_of?(pending_run, command.run_at) and
      DateTime.diff(command.triggered_at, pending_run.started_at) < @restart_after_seconds
  end

  defp settle(pending_run, run_at),
    do: if(run_of?(pending_run, run_at), do: nil, else: pending_run)

  defp run_of?(%PendingRun{run_at: pending_run_at}, run_at),
    do: DateTime.compare(pending_run_at, run_at) == :eq

  defp run_of?(nil, _), do: false

  # The same operation id each time the run of an occurrence starts again
  defp operation_id(schedule_id, run_at),
    do: UUID.uuid5(schedule_id, DateTime.to_iso8601(run_at))

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
