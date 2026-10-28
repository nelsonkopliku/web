# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ScheduleActivity do
  @moduledoc """
  What happens to an operation schedule, told to the activity log and to the
  UI.

  Every activity log entry of a schedule carries the schedule id as
  correlation id, and names the target the way the activity log expects, so
  that it adds the host name, cluster name or SID. The UI refreshes the
  schedules of the target.
  """

  alias Trento.ActivityLog.ActivityLogger
  alias Trento.Operations.{OperationSchedule, ScheduledRuns}

  @topic "monitoring:operation_schedules"

  @doc """
  Logs an activity of the schedule and tells the UI that the schedules of its
  target changed.
  """
  @spec record(atom(), OperationSchedule.t(), String.t(), map()) :: :ok
  def record(activity, %OperationSchedule{} = schedule, actor, extra \\ %{}) do
    ActivityLogger.log_application_activity(
      activity,
      actor,
      Map.merge(metadata(schedule), extra)
    )

    broadcast(schedule)
  end

  @doc """
  Tells the UI that the schedules of the target of the schedule changed.
  """
  @spec broadcast(OperationSchedule.t()) :: :ok
  def broadcast(%OperationSchedule{target_id: target_id}) do
    TrentoWeb.Endpoint.broadcast(@topic, "operation_schedules_changed", %{target_id: target_id})
    :ok
  end

  defp metadata(%OperationSchedule{id: id} = schedule) do
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
      recurrence: OperationSchedule.recurrence(schedule),
      next_run_at: schedule.next_run_at,
      bulk_id: schedule.bulk_id
    })
  end
end
