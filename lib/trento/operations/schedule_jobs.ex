# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ScheduleJobs do
  @moduledoc """
  The Oban job of an operation schedule: one job per schedule, at its next
  occurrence. Jobs are inserted, replaced and cancelled in the same
  transaction as the schedule.

  A job can be retried: it runs its occurrence only while the schedule is
  still due at that occurrence, so a retry never requests twice.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Trento.Operations.OperationSchedule

  @worker "Trento.Infrastructure.Jobs.ScheduledOperationJob"

  @spec worker() :: String.t()
  def worker, do: @worker

  @spec new(OperationSchedule.t()) :: Ecto.Changeset.t()
  def new(%OperationSchedule{id: id, next_run_at: next_run_at}) do
    Oban.Job.new(
      %{schedule_id: id, run_at: next_run_at},
      worker: @worker,
      queue: :operations,
      scheduled_at: next_run_at,
      max_attempts: 3
    )
  end

  @doc """
  Inserts the job of the schedule stored under `schedule_key` in the multi.
  """
  @spec insert(Multi.t(), term(), term()) :: Multi.t()
  def insert(multi, name, schedule_key),
    do: Oban.insert(multi, name, fn changes -> new(Map.fetch!(changes, schedule_key)) end)

  @doc """
  Cancels the pending jobs of a schedule.
  """
  @spec cancel(Multi.t(), term(), String.t()) :: Multi.t()
  def cancel(multi, name, schedule_id) do
    Multi.run(multi, name, fn _repo, _changes ->
      Oban.cancel_all_jobs(pending_jobs(schedule_id))
    end)
  end

  @doc """
  The pending jobs of a schedule.
  """
  @spec pending_jobs(String.t()) :: Ecto.Query.t()
  def pending_jobs(schedule_id) do
    from j in Oban.Job,
      where:
        j.worker == @worker and
          fragment("? @> ?", j.args, ^%{schedule_id: schedule_id}) and
          j.state in ["scheduled", "available", "retryable"]
  end
end
