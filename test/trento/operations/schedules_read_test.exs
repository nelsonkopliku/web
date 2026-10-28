# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.SchedulesReadTest do
  use ExUnit.Case, async: true
  use Trento.DataCase

  import Trento.Factory

  alias Trento.Operations.Projections.OperationScheduleReadModel
  alias Trento.Operations.Schedules

  defp schedule!(target_id, next_run_at, attrs \\ []) do
    insert(:operation_schedule, [target_id: target_id, next_run_at: next_run_at] ++ attrs)
  end

  test "should list the schedules of a target, the next one first" do
    host_id = UUID.uuid4()
    %{id: later} = schedule!(host_id, ~U[2026-11-09 02:00:00.000000Z])
    %{id: sooner} = schedule!(host_id, ~U[2026-11-07 02:00:00.000000Z])
    schedule!(UUID.uuid4(), ~U[2026-11-05 02:00:00.000000Z])

    assert [%OperationScheduleReadModel{id: ^sooner}, %OperationScheduleReadModel{id: ^later}] =
             Schedules.list_schedules(host_id)
  end

  test "should list the schedules of an operation on several targets" do
    [host_id, other_host_id, third_host_id] = Enum.map(1..3, fn _ -> UUID.uuid4() end)
    %{id: first} = schedule!(host_id, ~U[2026-11-07 02:00:00.000000Z])
    %{id: second} = schedule!(other_host_id, ~U[2026-11-08 02:00:00.000000Z])
    schedule!(third_host_id, ~U[2026-11-06 02:00:00.000000Z])

    %{id: other_operation} =
      schedule!(host_id, ~U[2026-11-06 02:00:00.000000Z],
        target_type: "sap_system",
        operation: "sap_system_stop"
      )

    assert [%OperationScheduleReadModel{id: ^first}, %OperationScheduleReadModel{id: ^second}] =
             Schedules.list_schedules([host_id, other_host_id], operation: "reboot")

    assert [%OperationScheduleReadModel{id: ^other_operation}] =
             Schedules.list_schedules([host_id, other_host_id], operation: "sap_system_stop")
  end

  test "should return no schedules for a target without any" do
    assert [] == Schedules.list_schedules(UUID.uuid4())
  end

  test "should get a schedule by id" do
    %{id: schedule_id} = schedule!(UUID.uuid4(), ~U[2026-11-07 02:00:00.000000Z])

    assert {:ok, %OperationScheduleReadModel{id: ^schedule_id}} =
             Schedules.get_schedule(schedule_id)

    assert {:error, :not_found} == Schedules.get_schedule(UUID.uuid4())
  end
end
