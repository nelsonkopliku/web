# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule TrentoWeb.V1.MaintenanceWindowJSON do
  alias Trento.MaintenanceWindows.Projections.MaintenanceWindowReadModel

  def maintenance_windows(%{maintenance_windows: windows}), do: Enum.map(windows, &window/1)

  def maintenance_window(%{maintenance_window: window}), do: window(window)

  def bulk_maintenance_windows(%{bulk_id: bulk_id, maintenance_windows: windows}),
    do: %{bulk_id: bulk_id, maintenance_windows: Enum.map(windows, &window/1)}

  defp window(%{window: %MaintenanceWindowReadModel{} = window} = covering) do
    window
    |> Map.take([
      :id,
      :target_type,
      :target_id,
      :starts_at,
      :timezone,
      :duration_minutes,
      :bulk_id,
      :created_by,
      :inserted_at,
      :updated_at
    ])
    |> Map.merge(%{
      recurrence: MaintenanceWindowReadModel.recurrence(window),
      forbids: MaintenanceWindowReadModel.forbids(window),
      target_name: covering.target_name,
      inherited: covering.inherited,
      active: covering.active,
      current_occurrence: covering.current_occurrence,
      next_occurrence: covering.next_occurrence
    })
  end
end
