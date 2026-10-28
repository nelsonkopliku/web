# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Projections.OperationScheduleProjectorTest do
  use ExUnit.Case
  use Trento.DataCase

  alias Trento.Operations.Events.OperationScheduled

  alias Trento.Operations.Projections.{
    OperationScheduleProjector,
    OperationScheduleReadModel
  }

  alias Trento.Operations.ValueObjects.{OperationParams, Recurrence}
  alias Trento.ProjectorTestHelper

  @moduletag :integration

  @starts_at ~U[2026-11-07 02:00:00.000000Z]

  setup do
    TrentoWeb.Endpoint.subscribe("monitoring:operation_schedules")
    :ok
  end

  defp project(event, metadata \\ %{}),
    do:
      ProjectorTestHelper.project(
        OperationScheduleProjector,
        event,
        metadata,
        "operation_schedule_projector"
      )

  test "should project a new schedule and tell the UI" do
    schedule_id = UUID.uuid4()
    target_id = UUID.uuid4()
    bulk_id = UUID.uuid4()

    project(
      %OperationScheduled{
        schedule_id: schedule_id,
        target_type: "database",
        target_id: target_id,
        operation: "database_start",
        params: %OperationParams{site: "Site1", timeout: 300},
        starts_at: @starts_at,
        timezone: "Europe/Berlin",
        recurrence: %Recurrence{
          frequency: :weekly,
          interval: 2,
          weekdays: [6, 7],
          ends_on: ~D[2027-01-01]
        },
        next_run_at: @starts_at,
        bulk_id: bulk_id
      },
      %{"created_by" => "admin"}
    )

    assert %OperationScheduleReadModel{
             id: ^schedule_id,
             target_type: "database",
             target_id: ^target_id,
             operation: "database_start",
             params: %{"site" => "Site1", "timeout" => 300},
             starts_at: @starts_at,
             timezone: "Europe/Berlin",
             frequency: :weekly,
             interval: 2,
             weekdays: [6, 7],
             ends_on: ~D[2027-01-01],
             max_occurrences: nil,
             next_run_at: @starts_at,
             occurrences: 0,
             bulk_id: ^bulk_id,
             created_by: "admin"
           } = Repo.get!(OperationScheduleReadModel, schedule_id)

    assert_receive %Phoenix.Socket.Broadcast{
      event: "operation_schedules_changed",
      payload: %{target_id: ^target_id}
    }
  end

  test "should project a one-time schedule without params" do
    schedule_id = UUID.uuid4()

    project(%OperationScheduled{
      schedule_id: schedule_id,
      target_type: "host",
      target_id: UUID.uuid4(),
      operation: "reboot",
      params: %OperationParams{},
      starts_at: @starts_at,
      timezone: "Etc/UTC",
      recurrence: nil,
      next_run_at: @starts_at
    })

    schedule = Repo.get!(OperationScheduleReadModel, schedule_id)

    assert %OperationScheduleReadModel{params: %{}, frequency: nil, created_by: nil} = schedule
    assert nil == OperationScheduleReadModel.recurrence(schedule)
  end
end
