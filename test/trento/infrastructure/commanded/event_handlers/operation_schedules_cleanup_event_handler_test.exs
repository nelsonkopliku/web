# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Infrastructure.Commanded.EventHandlers.OperationSchedulesCleanupEventHandlerTest do
  use ExUnit.Case
  use Trento.EventStoreCase
  use Trento.CommandedCase

  import Mox

  alias Trento.ActivityLog.ActivityLog
  alias Trento.Clusters.Events.ClusterDeregistered
  alias Trento.Databases.Events.DatabaseDeregistered
  alias Trento.Hosts.Events.HostDeregistered
  alias Trento.Infrastructure.Commanded.EventHandlers.OperationSchedulesCleanupEventHandler
  alias Trento.Operations.Commands.ScheduleOperation
  alias Trento.Operations.Projections.{OperationScheduleProjector, OperationScheduleReadModel}
  alias Trento.Repo
  alias Trento.SapSystems.Events.{ApplicationInstanceDeregistered, SapSystemDeregistered}

  @moduletag mocked_commanded: false

  defp schedule!(target_type, target_id, operation, params \\ %{}) do
    schedule_id = UUID.uuid4()

    :ok =
      %{
        schedule_id: schedule_id,
        target_type: target_type,
        target_id: target_id,
        operation: operation,
        params: params,
        starts_at: ~U[2026-11-07 02:00:00.000000Z],
        timezone: "Etc/UTC",
        requested_at: ~U[2026-11-02 10:00:00.000000Z]
      }
      |> ScheduleOperation.new!()
      |> Trento.Commanded.dispatch(consistency: [OperationScheduleProjector])

    schedule_id
  end

  defp remaining, do: OperationScheduleReadModel |> Repo.all() |> Enum.map(& &1.id)

  test "should cancel the schedules of a deregistered host and of its SAP instances" do
    host_id = UUID.uuid4()
    sap_system_id = UUID.uuid4()
    schedule!("host", host_id, "reboot")

    schedule!("sap_system", sap_system_id, "sap_instance_start", %{
      host_id: host_id,
      instance_number: "10"
    })

    kept = schedule!("host", UUID.uuid4(), "reboot")
    correlation_id = UUID.uuid4()
    metadata = %{correlation_id: correlation_id, event_id: UUID.uuid4()}
    event = %HostDeregistered{host_id: host_id, deregistered_at: DateTime.utc_now()}

    assert :ok == OperationSchedulesCleanupEventHandler.handle(event, metadata)
    assert [kept] == remaining()

    assert [
             %ActivityLog{actor: "system", metadata: %{"correlation_id" => ^correlation_id}},
             %ActivityLog{actor: "system", metadata: %{"correlation_id" => ^correlation_id}}
           ] = Repo.all(ActivityLog)

    # handling the deregistration again changes nothing
    assert :ok == OperationSchedulesCleanupEventHandler.handle(event, metadata)
    assert 2 == length(Repo.all(ActivityLog))
  end

  test "should cancel the SAP instance schedules of a deregistered instance" do
    sap_system_id = UUID.uuid4()
    host_id = UUID.uuid4()

    schedule!("sap_system", sap_system_id, "sap_instance_start", %{
      host_id: host_id,
      instance_number: "10"
    })

    kept =
      schedule!("sap_system", sap_system_id, "sap_instance_start", %{
        host_id: host_id,
        instance_number: "11"
      })

    assert :ok ==
             OperationSchedulesCleanupEventHandler.handle(
               %ApplicationInstanceDeregistered{
                 sap_system_id: sap_system_id,
                 host_id: host_id,
                 instance_number: "10",
                 deregistered_at: DateTime.utc_now()
               },
               %{correlation_id: UUID.uuid4()}
             )

    assert [kept] == remaining()
  end

  test "should cancel the schedules of a deregistered cluster, SAP system or database" do
    cluster_id = UUID.uuid4()
    sap_system_id = UUID.uuid4()
    database_id = UUID.uuid4()
    schedule!("cluster", cluster_id, "cluster_maintenance_change", %{maintenance: true})
    schedule!("sap_system", sap_system_id, "sap_system_stop")
    schedule!("database", database_id, "database_stop")

    for event <- [
          %ClusterDeregistered{cluster_id: cluster_id, deregistered_at: DateTime.utc_now()},
          %SapSystemDeregistered{
            sap_system_id: sap_system_id,
            deregistered_at: DateTime.utc_now()
          },
          %DatabaseDeregistered{database_id: database_id, deregistered_at: DateTime.utc_now()}
        ] do
      assert :ok == OperationSchedulesCleanupEventHandler.handle(event, %{})
    end

    assert [] == remaining()
  end

  @tag mocked_commanded: true
  test "should return the error of a schedule that cannot be cancelled, so that it is retried" do
    host_id = UUID.uuid4()
    Trento.Factory.insert(:operation_schedule, target_id: host_id)
    expect(Trento.Commanded.Mock, :dispatch, fn _, _ -> {:error, :event_store_unavailable} end)

    assert {:error, :event_store_unavailable} ==
             OperationSchedulesCleanupEventHandler.handle(
               %HostDeregistered{host_id: host_id, deregistered_at: DateTime.utc_now()},
               %{}
             )
  end
end
