# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Scheduler do
  @moduledoc """
  Runs the due operation schedules. A Quantum job calls `run_due/1` every minute.

  For each schedule whose next_run_at is past:

  - later than the grace period: the request failed because Trento was not available
  - otherwise the operation policies run on fresh data, and the operation is
    requested when they pass; the run is recorded with its operation id
  - a request that cannot be sent leaves the schedule due, so the next run
    retries it until the grace period ends

  Then a one-time schedule is removed, and a periodic one moves to its next
  occurrence after now. Occurrences missed meanwhile count as done.

  Each schedule is handled in its own transaction, locked with
  FOR UPDATE SKIP LOCKED, so a slow request does not hold the others, and a
  failing schedule does not stop the others.
  """

  import Ecto.Query, only: [from: 2]

  alias Trento.Operations.{OperationSchedule, Requests, ScheduleActivity, ScheduledRuns}
  alias Trento.Repo
  alias Trento.Scheduling.Recurrence
  alias Trento.Support.DateService

  require Logger

  @grace_period_seconds 300

  @spec grace_period_seconds() :: pos_integer()
  def grace_period_seconds, do: @grace_period_seconds

  @spec run_due(module()) :: :ok
  def run_due(date_service \\ DateService) do
    now = date_service.utc_now()

    Repo.all(
      from s in OperationSchedule,
        where: s.next_run_at <= ^now,
        order_by: [asc: s.next_run_at],
        select: s.id
    )
    |> Enum.each(&run_isolated(&1, now))
  end

  defp run_isolated(schedule_id, now) do
    run(schedule_id, now)
  rescue
    error ->
      Logger.error(
        "Operation schedule #{schedule_id} could not run: #{Exception.format(:error, error, __STACKTRACE__)}"
      )
  end

  defp run(schedule_id, now) do
    Repo.transaction(fn ->
      case Repo.one(
             from s in OperationSchedule,
               where: s.id == ^schedule_id and s.next_run_at <= ^now,
               lock: "FOR UPDATE SKIP LOCKED"
           ) do
        nil -> :skipped
        schedule -> handle(schedule, now)
      end
    end)
    |> case do
      {:ok, {activity, schedule, extra}} ->
        ScheduleActivity.record(activity, schedule, "system", extra)

      {:ok, :skipped} ->
        :ok

      {:error, :retry} ->
        :ok
    end
  end

  defp handle(%OperationSchedule{next_run_at: run_at} = schedule, now) do
    case outcome(schedule, now) do
      :retry ->
        Repo.rollback(:retry)

      {activity, extra} ->
        advance(schedule, now)
        {activity, schedule, Map.put(extra, :run_at, run_at)}
    end
  end

  defp outcome(%OperationSchedule{next_run_at: run_at} = schedule, now) do
    if DateTime.diff(now, run_at) > @grace_period_seconds do
      {:scheduled_operation_request_failed, %{reason: "not_available"}}
    else
      request(schedule)
    end
  end

  defp request(%OperationSchedule{} = schedule) do
    {:ok, target_type, operation} = Requests.parse(schedule.target_type, schedule.operation)

    case Requests.request(target_type, schedule.target_id, operation, schedule.params) do
      {:ok, operation_id} ->
        record_run(schedule, operation_id)
        {:scheduled_operation_requested, %{operation_id: operation_id}}

      {:error, :forbidden, errors} ->
        {:scheduled_operation_request_failed, %{reason: "policies", errors: errors}}

      {:error, :maintenance_window, errors} ->
        {:scheduled_operation_request_failed, %{reason: "maintenance_window", errors: errors}}

      {:error, :not_found} ->
        {:scheduled_operation_request_failed, %{reason: "target_not_found"}}

      {:error, reason} ->
        Logger.warning(
          "Scheduled operation #{schedule.id} could not be requested, retrying: #{inspect(reason)}"
        )

        :retry
    end
  end

  defp record_run(%OperationSchedule{} = schedule, operation_id) do
    %{
      operation_id: operation_id,
      schedule_id: schedule.id,
      run_at: schedule.next_run_at,
      target_type: schedule.target_type,
      target_id: schedule.target_id,
      operation: schedule.operation,
      params: schedule.params
    }
    |> ScheduledRuns.changeset()
    |> Repo.insert!()
  end

  # The handled occurrence counts, and so does every occurrence missed until
  # now: they are not caught up.
  defp advance(%OperationSchedule{occurrences: occurrences, next_run_at: run_at} = schedule, now) do
    case next_occurrence(schedule, occurrences + 1, run_at, now) do
      {_, nil} ->
        Repo.delete!(schedule)

      {done, next_run_at} ->
        schedule
        |> Ecto.Changeset.change(next_run_at: next_run_at, occurrences: done)
        |> Repo.update!()
    end
  end

  defp next_occurrence(%OperationSchedule{} = schedule, done, after_instant, now) do
    recurrence = OperationSchedule.to_recurrence(%{schedule | occurrences: done})

    case Recurrence.next_occurrence(recurrence, after_instant) do
      nil ->
        {done, nil}

      next ->
        if DateTime.compare(next, now) == :gt,
          do: {done, next},
          else: next_occurrence(schedule, done + 1, next, now)
    end
  end
end
