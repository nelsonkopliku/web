# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Scheduler do
  @moduledoc """
  Runs one occurrence of an operation schedule. The Oban job of the schedule
  calls `run/3` at the scheduled time.

  - later than the grace period: the request failed because Trento was not available
  - otherwise the operation policies run on fresh data, and the operation is
    requested when they pass; the run is recorded with its operation id
  - a request that cannot be sent snoozes the job, which retries it until the
    grace period ends

  Then a one-time schedule is removed, and a periodic one moves to its next
  occurrence after now, with a new job. The occurrences missed meanwhile
  count as done.

  A job whose occurrence is not the next one of its schedule (the schedule
  changed or ran after it was enqueued) does nothing, so a retried job never
  requests twice. `reconcile/1` gives a job back to a due schedule that lost
  its own, for example after a database restore.
  """

  import Ecto.Query, only: [from: 2]

  alias Trento.Operations.{
    OperationSchedule,
    Requests,
    ScheduleActivity,
    ScheduledRuns,
    ScheduleJobs
  }

  alias Trento.Repo
  alias Trento.Scheduling.Recurrence
  alias Trento.Support.DateService

  require Logger

  @grace_period_seconds 300
  @snooze_seconds 60

  @spec grace_period_seconds() :: pos_integer()
  def grace_period_seconds, do: @grace_period_seconds

  @spec run(String.t(), DateTime.t(), module()) :: :ok | {:snooze, pos_integer()}
  def run(schedule_id, run_at, date_service \\ DateService) do
    now = date_service.utc_now()

    Repo.transaction(fn ->
      case Repo.one(from s in OperationSchedule, where: s.id == ^schedule_id, lock: "FOR UPDATE") do
        %OperationSchedule{next_run_at: next_run_at} = schedule ->
          if DateTime.compare(next_run_at, run_at) == :eq,
            do: handle(schedule, now),
            else: :stale

        nil ->
          :stale
      end
    end)
    |> case do
      {:ok, {activity, schedule, extra}} ->
        ScheduleActivity.record(activity, schedule, "system", extra)

      {:ok, :stale} ->
        :ok

      {:error, :retry} ->
        {:snooze, @snooze_seconds}
    end
  end

  @doc """
  Inserts a job for every due or future schedule without a pending job.
  """
  @spec reconcile() :: :ok
  def reconcile do
    Repo.all(
      from s in OperationSchedule,
        as: :schedule,
        where:
          not exists(
            from j in Oban.Job,
              where:
                j.worker == ^ScheduleJobs.worker() and
                  fragment("?->>'schedule_id' = ?::text", j.args, parent_as(:schedule).id) and
                  j.state in ["scheduled", "available", "executing", "retryable"]
          )
    )
    |> Enum.each(fn schedule ->
      Logger.warning("Operation schedule #{schedule.id} had no pending job, enqueuing it")
      schedule |> ScheduleJobs.new() |> Oban.insert!()
    end)
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
        |> ScheduleJobs.new()
        |> Oban.insert!()
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
