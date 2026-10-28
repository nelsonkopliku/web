# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Projections.MaintenanceWindowProjector do
  @moduledoc """
  Projects the maintenance windows into the maintenance_windows read model,
  which the coverage, the lists and the policies read.

  The maintenance windows API waits for this projector after a change, so
  that it answers with the projected window: the projector registers for
  strong consistency. The UI is told that the windows of the target changed.
  """

  use Commanded.Projections.Ecto,
    application: Trento.Commanded,
    repo: Trento.Repo,
    name: "maintenance_window_projector",
    consistency: :strong

  alias Trento.MaintenanceWindows.Events.MaintenanceWindowScheduled
  alias Trento.MaintenanceWindows.Projections.MaintenanceWindowReadModel
  alias Trento.MaintenanceWindows.ValueObjects.Recurrence

  @topic "monitoring:maintenance_windows"

  project(%MaintenanceWindowScheduled{} = event, metadata, fn multi ->
    changeset =
      MaintenanceWindowReadModel.changeset(
        %MaintenanceWindowReadModel{},
        event
        |> timing()
        |> Map.merge(%{
          id: event.window_id,
          target_type: event.target_type,
          target_id: event.target_id,
          bulk_id: event.bulk_id,
          created_by: Map.get(metadata, "created_by")
        })
      )

    Ecto.Multi.insert(multi, :maintenance_window, changeset)
  end)

  @impl true
  def after_update(_event, _metadata, %{
        maintenance_window: %MaintenanceWindowReadModel{target_type: type, target_id: id}
      }) do
    TrentoWeb.Endpoint.broadcast(@topic, "maintenance_windows_changed", %{
      target_type: type,
      target_id: id
    })
  end

  def after_update(_event, _metadata, _changes), do: :ok

  # The timing and the forbidden actions of a window, as the read model keeps them.
  defp timing(%{recurrence: recurrence, forbids: forbids} = event) do
    Map.merge(
      %{
        starts_at: event.starts_at,
        timezone: event.timezone,
        duration_minutes: event.duration_minutes,
        forbid_checks_execution: :checks_execution in forbids,
        forbid_operations: :operations in forbids
      },
      recurrence_fields(recurrence)
    )
  end

  defp recurrence_fields(nil), do: %{frequency: nil, interval: 1, weekdays: [], ends_on: nil}

  defp recurrence_fields(%Recurrence{} = recurrence) do
    %{
      frequency: Atom.to_string(recurrence.frequency),
      interval: recurrence.interval,
      weekdays: recurrence.weekdays,
      ends_on: recurrence.ends_on
    }
  end
end
