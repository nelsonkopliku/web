# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.WindowActivity do
  @moduledoc """
  What happens to a maintenance window, told to the activity log and to the
  UI.

  Every activity log entry of a window carries the window id as correlation
  id, and names its target the way the activity log expects, so that it adds
  the host name, cluster name or SID. The UI refreshes the windows of the
  targets on display.
  """

  alias Trento.ActivityLog.ActivityLogger
  alias Trento.MaintenanceWindows.MaintenanceWindow
  alias Trento.Operations.ScheduledRuns

  @topic "monitoring:maintenance_windows"

  @spec record(atom(), MaintenanceWindow.t(), String.t(), map()) :: :ok
  def record(activity, %MaintenanceWindow{} = window, actor, extra \\ %{}) do
    ActivityLogger.log_application_activity(activity, actor, Map.merge(metadata(window), extra))
    broadcast(window)
  end

  @spec broadcast(MaintenanceWindow.t()) :: :ok
  def broadcast(%MaintenanceWindow{target_type: target_type, target_id: target_id}) do
    TrentoWeb.Endpoint.broadcast(@topic, "maintenance_windows_changed", %{
      target_type: target_type,
      target_id: target_id
    })

    :ok
  end

  defp metadata(%MaintenanceWindow{id: id} = window) do
    window.target_type
    |> ScheduledRuns.target_metadata(window.target_id)
    |> Map.merge(%{
      maintenance_window_id: id,
      correlation_id: id,
      target_type: window.target_type,
      starts_at: window.starts_at,
      timezone: window.timezone,
      duration_minutes: window.duration_minutes,
      recurrence: MaintenanceWindow.recurrence(window),
      forbids: MaintenanceWindow.forbids(window),
      bulk_id: window.bulk_id
    })
  end
end
