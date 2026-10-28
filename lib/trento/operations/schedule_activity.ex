# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ScheduleActivity do
  @moduledoc """
  What happens to an operation schedule, told to the activity log.

  The events of a schedule do not name who changed it, so the activity log
  does not take them from the event store: whoever dispatches a command to a
  schedule logs what it did, once the command succeeded. Users for the
  changes they make, the system for the runs and the clean up.

  Every entry carries the schedule id as correlation id, and names the target
  the way the activity log expects, so that it adds the host name, cluster
  name or SID.
  """

  alias Trento.ActivityLog.ActivityLogger
  alias Trento.Operations.Projections.OperationScheduleReadModel
  alias Trento.Operations.ScheduledRuns

  @spec record(atom(), OperationScheduleReadModel.t(), String.t(), map()) :: :ok
  def record(activity, %OperationScheduleReadModel{} = schedule, actor, extra \\ %{}),
    do:
      ActivityLogger.log_application_activity(
        activity,
        actor,
        Map.merge(metadata(schedule), extra)
      )

  defp metadata(%OperationScheduleReadModel{id: id} = schedule) do
    schedule.target_type
    |> ScheduledRuns.target_metadata(schedule.target_id)
    |> Map.merge(%{
      schedule_id: id,
      correlation_id: id,
      target_type: schedule.target_type,
      operation: schedule.operation,
      params: schedule.params,
      starts_at: schedule.starts_at,
      timezone: schedule.timezone,
      recurrence: OperationScheduleReadModel.recurrence(schedule),
      next_run_at: schedule.next_run_at,
      bulk_id: schedule.bulk_id
    })
  end
end
