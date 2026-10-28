# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Scheduler do
  @moduledoc """
  Runs the due occurrences of the operation schedules. A Quantum job calls
  `run_due/1` every minute.

  For each schedule whose next occurrence is due, the aggregate decides what
  the occurrence means:

  - later than the grace period, it failed because Trento was not available
  - otherwise a run starts, with the operation id to request; the operation
    policies run on fresh data and the operation is requested when they
    pass, and the outcome goes back to the aggregate, which moves the
    schedule to its next occurrence or ends it
  - a stale trigger, or a run that started a moment ago, is refused

  A request that cannot be sent leaves the run pending: the next run starts
  it again with the same operation id, until the grace period ends. Nothing
  retries here, and nothing is requested again by a replay of the events.

  Each command waits for the read model of the schedules, and the outcome of
  a run for the record of the run too, so that the next run of the job reads
  the schedules as the aggregates left them, and a reply of Wanda finds its
  schedule as soon as possible.

  Every outcome is logged, correlated to the schedule. A schedule that cannot
  run is logged and does not stop the others.
  """

  import Ecto.Query, only: [from: 2]

  alias Commanded.Commands.ExecutionResult
  alias Trento.Operations.Commands.{CompleteScheduledRun, TriggerScheduledRun}
  alias Trento.Operations.Events.{ScheduledOperationRequestFailed, ScheduledRunStarted}

  alias Trento.Operations.Projections.{
    OperationScheduleProjector,
    OperationScheduleReadModel,
    ScheduledRunProjector
  }

  alias Trento.Operations.{Requests, Schedule, ScheduleActivity}
  alias Trento.Operations.ValueObjects.OperationParams
  alias Trento.Repo
  alias Trento.Support.{CommandedUtils, DateService}

  require Logger

  @refused [
    :operation_schedule_not_found,
    :operation_schedule_run_pending,
    :operation_schedule_stale_run
  ]

  @spec run_due(module()) :: :ok
  def run_due(date_service \\ DateService) do
    now = date_service.utc_now()

    due =
      Repo.all(
        from s in OperationScheduleReadModel,
          where: s.next_run_at <= ^now,
          order_by: [asc: s.next_run_at]
      )

    Enum.each(due, &run_isolated(&1, now))
  end

  defp run_isolated(%OperationScheduleReadModel{id: schedule_id} = schedule, now) do
    run(schedule, now)
  rescue
    error ->
      Logger.error(
        "Operation schedule #{schedule_id} could not run: #{Exception.format(:error, error, __STACKTRACE__)}"
      )
  end

  # The commands of a run share a correlation id
  defp run(%OperationScheduleReadModel{} = schedule, now) do
    correlation_id = UUID.uuid4()
    cause = [correlation_id: correlation_id, causation_id: correlation_id]

    %{schedule_id: schedule.id, run_at: schedule.next_run_at, triggered_at: now}
    |> TriggerScheduledRun.new!()
    |> CommandedUtils.dispatch(
      [consistency: [OperationScheduleProjector], include_execution_result: true] ++ cause
    )
    |> case do
      {:ok, %ExecutionResult{events: events}} ->
        Enum.each(events, &handle(&1, schedule, now, cause))

      {:error, :consistency_timeout} ->
        late(schedule, now)

      {:error, reason} when reason in @refused ->
        :ok

      {:error, reason} ->
        Logger.error("Operation schedule #{schedule.id} could not run: #{inspect(reason)}")
    end
  end

  # The trigger went through, its events are not known: a late occurrence
  # failed, otherwise the run is pending and starts again at the next run.
  defp late(%OperationScheduleReadModel{next_run_at: run_at} = schedule, now) do
    Logger.warning(
      "Operation schedule #{schedule.id} triggered, its read model is not up to date"
    )

    if DateTime.diff(now, run_at) > Schedule.grace_period_seconds(),
      do:
        handle(
          %ScheduledOperationRequestFailed{run_at: run_at, reason: :not_available},
          schedule,
          now,
          []
        )
  end

  defp handle(%ScheduledRunStarted{} = run, schedule, now, cause) do
    run
    |> request()
    |> complete(run, schedule, now, cause)
  end

  defp handle(%ScheduledOperationRequestFailed{run_at: run_at, reason: reason}, schedule, _, _),
    do:
      ScheduleActivity.record(:scheduled_operation_request_failed, schedule, "system", %{
        run_at: run_at,
        reason: reason
      })

  defp request(%ScheduledRunStarted{} = run) do
    {:ok, target_type, operation} = Requests.parse(run.target_type, run.operation)
    params = OperationParams.to_map(run.params)

    case Requests.request(target_type, run.target_id, operation, params, run.operation_id) do
      {:ok, operation_id} -> {:requested, %{operation_id: operation_id}}
      {:error, :forbidden, errors} -> {:failed, %{reason: :policies, errors: errors}}
      {:error, :not_found} -> {:failed, %{reason: :target_not_found, errors: []}}
      {:error, reason} -> {:not_sent, reason}
    end
  end

  defp complete({:not_sent, reason}, run, _, _, _) do
    Logger.warning(
      "Operation schedule #{run.schedule_id}: the operation of #{run.run_at} could not be requested, retrying at the next run: #{inspect(reason)}"
    )
  end

  defp complete({outcome, details}, run, schedule, now, cause) do
    %{schedule_id: run.schedule_id, run_at: run.run_at, outcome: outcome, completed_at: now}
    |> Map.merge(details)
    |> CompleteScheduledRun.new!()
    |> CommandedUtils.dispatch(
      [consistency: [OperationScheduleProjector, ScheduledRunProjector]] ++ cause
    )
    |> case do
      result when result in [:ok, {:error, :consistency_timeout}] ->
        ScheduleActivity.record(
          activity(outcome),
          schedule,
          "system",
          Map.put(details, :run_at, run.run_at)
        )

      {:error, reason} ->
        Logger.error(
          "Operation schedule #{run.schedule_id}: the outcome of #{run.run_at} could not be recorded, the run starts again at the next run: #{inspect(reason)}"
        )
    end
  end

  defp activity(:requested), do: :scheduled_operation_requested
  defp activity(:failed), do: :scheduled_operation_request_failed
end
