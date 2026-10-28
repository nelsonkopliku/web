# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.WindowActivity do
  @moduledoc """
  What happens to a maintenance window, told to the activity log.

  The events of a window do not name who changed it, so the activity log
  does not take them from the event store: whoever dispatches a command to a
  window logs what it did, once the command succeeded. Users for the changes
  they make, the system for the clean up.

  Every activity log entry of a window carries the window id as correlation
  id, and names its target the way the activity log expects, so that it adds
  the host name, cluster name or SID.
  """

  alias Trento.ActivityLog.ActivityLogger
  alias Trento.MaintenanceWindows.Projections.MaintenanceWindowReadModel
  alias Trento.Operations.ScheduledRuns

  @spec record(atom(), MaintenanceWindowReadModel.t(), String.t(), map()) :: :ok
  def record(activity, %MaintenanceWindowReadModel{} = window, actor, extra \\ %{}),
    do:
      ActivityLogger.log_application_activity(activity, actor, Map.merge(metadata(window), extra))

  defp metadata(%MaintenanceWindowReadModel{id: id} = window) do
    window.target_type
    |> ScheduledRuns.target_metadata(window.target_id)
    |> Map.merge(%{
      maintenance_window_id: id,
      correlation_id: id,
      target_type: window.target_type,
      starts_at: window.starts_at,
      timezone: window.timezone,
      duration_minutes: window.duration_minutes,
      recurrence: MaintenanceWindowReadModel.recurrence(window),
      forbids: MaintenanceWindowReadModel.forbids(window),
      bulk_id: window.bulk_id
    })
  end
end
