# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Projections.MaintenanceWindowProjectorTest do
  use ExUnit.Case
  use Trento.DataCase

  alias Trento.MaintenanceWindows.Events.{MaintenanceWindowChanged, MaintenanceWindowScheduled}

  alias Trento.MaintenanceWindows.Projections.{
    MaintenanceWindowProjector,
    MaintenanceWindowReadModel
  }

  alias Trento.MaintenanceWindows.ValueObjects.Recurrence
  alias Trento.ProjectorTestHelper

  import Trento.Factory

  @moduletag :integration

  @starts_at ~U[2026-11-07 22:00:00.000000Z]

  setup do
    TrentoWeb.Endpoint.subscribe("monitoring:maintenance_windows")
    :ok
  end

  defp project(event, metadata \\ %{}),
    do:
      ProjectorTestHelper.project(
        MaintenanceWindowProjector,
        event,
        metadata,
        "maintenance_window_projector"
      )

  test "should project a new window and tell the UI" do
    window_id = UUID.uuid4()
    target_id = UUID.uuid4()
    bulk_id = UUID.uuid4()

    project(
      %MaintenanceWindowScheduled{
        window_id: window_id,
        target_type: "database",
        target_id: target_id,
        starts_at: @starts_at,
        timezone: "Europe/Berlin",
        duration_minutes: 240,
        recurrence: %Recurrence{
          frequency: :weekly,
          interval: 2,
          weekdays: [6],
          ends_on: ~D[2027-01-01]
        },
        forbids: [:operations],
        bulk_id: bulk_id
      },
      %{"created_by" => "admin"}
    )

    assert %MaintenanceWindowReadModel{
             id: ^window_id,
             target_type: "database",
             target_id: ^target_id,
             starts_at: @starts_at,
             timezone: "Europe/Berlin",
             duration_minutes: 240,
             frequency: "weekly",
             interval: 2,
             weekdays: [6],
             ends_on: ~D[2027-01-01],
             forbid_checks_execution: false,
             forbid_operations: true,
             bulk_id: ^bulk_id,
             created_by: "admin"
           } = window = Repo.get!(MaintenanceWindowReadModel, window_id)

    assert ["operations"] == MaintenanceWindowReadModel.forbids(window)

    assert_receive %Phoenix.Socket.Broadcast{
      event: "maintenance_windows_changed",
      payload: %{target_type: "database", target_id: ^target_id}
    }
  end

  test "should project a one-time window" do
    window_id = UUID.uuid4()

    project(%MaintenanceWindowScheduled{
      window_id: window_id,
      target_type: "host",
      target_id: UUID.uuid4(),
      starts_at: @starts_at,
      timezone: "Etc/UTC",
      duration_minutes: 60,
      recurrence: nil,
      forbids: [:checks_execution, :operations]
    })

    window = Repo.get!(MaintenanceWindowReadModel, window_id)

    assert %MaintenanceWindowReadModel{frequency: nil, interval: 1, weekdays: []} = window
    assert nil == MaintenanceWindowReadModel.recurrence(window)
    assert ["checks_execution", "operations"] == MaintenanceWindowReadModel.forbids(window)
  end

  test "should project a change of the timing and the forbidden actions" do
    target_id = UUID.uuid4()

    %{id: window_id} =
      insert(:maintenance_window,
        target_type: "cluster",
        target_id: target_id,
        frequency: "daily",
        created_by: "admin"
      )

    project(%MaintenanceWindowChanged{
      window_id: window_id,
      starts_at: @starts_at,
      timezone: "Europe/Berlin",
      duration_minutes: 30,
      recurrence: nil,
      forbids: [:checks_execution]
    })

    assert %MaintenanceWindowReadModel{
             starts_at: @starts_at,
             timezone: "Europe/Berlin",
             duration_minutes: 30,
             frequency: nil,
             forbid_checks_execution: true,
             forbid_operations: false,
             created_by: "admin"
           } = Repo.get!(MaintenanceWindowReadModel, window_id)

    assert_receive %Phoenix.Socket.Broadcast{
      event: "maintenance_windows_changed",
      payload: %{target_type: "cluster", target_id: ^target_id}
    }
  end
end
