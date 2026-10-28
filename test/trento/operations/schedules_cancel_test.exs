# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.SchedulesCancelTest do
  use ExUnit.Case
  use Trento.EventStoreCase
  use Trento.CommandedCase

  import Mox
  import Trento.Factory

  alias Trento.ActivityLog.ActivityLog
  alias Trento.Operations.Commands.ScheduleOperation
  alias Trento.Operations.Projections.{OperationScheduleProjector, OperationScheduleReadModel}
  alias Trento.Operations.Schedules
  alias Trento.Repo
  alias Trento.Support.DateService

  @moduletag mocked_commanded: false

  setup do
    stub(DateService.Mock, :utc_now, fn -> ~U[2026-11-02 10:00:00.000000Z] end)
    %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)
    %{host_id: host_id}
  end

  defp schedule!(host_id) do
    {:ok, schedule, _} =
      Schedules.create_schedule(
        %{
          target_type: "host",
          target_id: host_id,
          operation: "reboot",
          starts_at: ~U[2026-11-07 02:00:00.000000Z],
          timezone: "Etc/UTC"
        },
        "admin",
        DateService.Mock
      )

    schedule
  end

  # A SAP instance schedule, without the target the policies need
  defp instance_schedule!(sap_system_id, host_id, instance_number) do
    schedule_id = UUID.uuid4()

    :ok =
      %{
        schedule_id: schedule_id,
        target_type: "sap_system",
        target_id: sap_system_id,
        operation: "sap_instance_stop",
        params: %{host_id: host_id, instance_number: instance_number},
        starts_at: ~U[2026-11-07 02:00:00.000000Z],
        timezone: "Etc/UTC",
        requested_at: ~U[2026-11-02 10:00:00.000000Z]
      }
      |> ScheduleOperation.new!()
      |> Trento.Commanded.dispatch(consistency: [OperationScheduleProjector])

    schedule_id
  end

  test "should cancel a schedule and log it", %{host_id: host_id} do
    %{id: schedule_id} = schedule!(host_id)

    assert :ok == Schedules.cancel_schedule(schedule_id, "operator")
    assert {:error, :not_found} == Schedules.get_schedule(schedule_id)

    assert %ActivityLog{
             actor: "operator",
             metadata: %{"correlation_id" => ^schedule_id, "host_id" => ^host_id}
           } = Repo.get_by!(ActivityLog, type: "operation_schedule_cancelled")
  end

  test "should not find an unknown or already cancelled schedule", %{host_id: host_id} do
    %{id: schedule_id} = schedule!(host_id)

    assert :ok == Schedules.cancel_schedule(schedule_id, "operator")
    assert {:error, :not_found} == Schedules.cancel_schedule(schedule_id, "operator")
    assert {:error, :not_found} == Schedules.cancel_schedule(UUID.uuid4(), "operator")
  end

  @tag mocked_commanded: true
  test "should not find a schedule that the read model still shows but is cancelled" do
    %{id: schedule_id} = insert(:operation_schedule)

    expect(Trento.Commanded.Mock, :dispatch, 2, fn _, _ ->
      {:error, :operation_schedule_not_found}
    end)

    assert {:error, :not_found} == Schedules.cancel_schedule(schedule_id, "operator")

    assert {:error, :not_found} ==
             Schedules.update_schedule(
               schedule_id,
               %{starts_at: ~U[2026-11-10 04:00:00.000000Z], timezone: "Etc/UTC"},
               "operator",
               DateService.Mock
             )

    assert [] == Repo.all(ActivityLog)
  end

  test "should cancel the SAP instance schedules of a removed instance or host" do
    sap_system_id = UUID.uuid4()
    host_id = UUID.uuid4()
    other_host_id = UUID.uuid4()

    removed_instance = instance_schedule!(sap_system_id, host_id, "00")
    other_instance = instance_schedule!(sap_system_id, host_id, "01")
    other_host = instance_schedule!(sap_system_id, other_host_id, "00")

    :ok =
      Schedules.cancel_instance_schedules(
        [sap_system_id: sap_system_id, host_id: host_id, instance_number: "00"],
        []
      )

    assert Enum.sort([other_instance, other_host]) ==
             OperationScheduleReadModel |> Repo.all() |> Enum.map(& &1.id) |> Enum.sort()

    :ok = Schedules.cancel_instance_schedules([host_id: host_id], [])

    assert [%OperationScheduleReadModel{id: ^other_host}] = Repo.all(OperationScheduleReadModel)

    assert Enum.sort([removed_instance, other_instance]) ==
             ActivityLog
             |> Repo.all()
             |> Enum.map(& &1.metadata["schedule_id"])
             |> Enum.sort()
  end

  test "should cancel the schedules of a removed target, correlated to the clean up", %{
    host_id: host_id
  } do
    %{id: first} = schedule!(host_id)
    %{id: second} = schedule!(host_id)
    %{id: other_host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)
    %{id: kept} = schedule!(other_host_id)
    cleanup_correlation_id = UUID.uuid4()

    assert :ok ==
             Schedules.cancel_target_schedules(host_id,
               correlation_id: cleanup_correlation_id,
               causation_id: UUID.uuid4()
             )

    assert [%OperationScheduleReadModel{id: ^kept}] = Repo.all(OperationScheduleReadModel)

    cancelled =
      ActivityLog
      |> Repo.all()
      |> Enum.filter(&(&1.type == "operation_schedule_cancelled"))

    assert Enum.sort([first, second]) ==
             cancelled |> Enum.map(& &1.metadata["schedule_id"]) |> Enum.sort()

    assert Enum.all?(
             cancelled,
             &match?(
               %ActivityLog{
                 actor: "system",
                 metadata: %{"correlation_id" => ^cleanup_correlation_id}
               },
               &1
             )
           )
  end

  test "should skip the schedules cancelled meanwhile when cleaning up", %{host_id: host_id} do
    %{id: schedule_id} = schedule!(host_id)
    :ok = Schedules.cancel_schedule(schedule_id, "operator")

    # the read model still shows the schedule to the clean up
    insert(:operation_schedule, id: schedule_id, target_id: host_id)

    assert :ok == Schedules.cancel_target_schedules(host_id, [])
    assert [_] = Enum.filter(Repo.all(ActivityLog), &(&1.type == "operation_schedule_cancelled"))
  end
end
