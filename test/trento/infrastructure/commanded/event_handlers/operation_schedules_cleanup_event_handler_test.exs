# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Infrastructure.Commanded.EventHandlers.OperationSchedulesCleanupEventHandlerTest do
  use ExUnit.Case, async: true
  use Trento.DataCase

  import Mox
  import Trento.Factory

  alias Trento.Clusters.Events.ClusterDeregistered
  alias Trento.Databases.Events.DatabaseDeregistered
  alias Trento.Hosts.Events.HostDeregistered
  alias Trento.Infrastructure.Commanded.EventHandlers.OperationSchedulesCleanupEventHandler
  alias Trento.Operations.{OperationSchedule, Schedules}
  alias Trento.SapSystems.Events.{ApplicationInstanceDeregistered, SapSystemDeregistered}
  alias Trento.Support.DateService

  setup do
    stub(DateService.Mock, :utc_now, fn -> ~U[2026-11-02 10:00:00.000000Z] end)
    :ok
  end

  test "should cancel the schedules of a deregistered host" do
    %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)

    {:ok, _, _} =
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

    assert :ok ==
             OperationSchedulesCleanupEventHandler.handle(
               %HostDeregistered{host_id: host_id, deregistered_at: DateTime.utc_now()},
               %{correlation_id: UUID.uuid4()}
             )

    assert [] == Repo.all(OperationSchedule)
  end

  test "should cancel the SAP instance schedules of a deregistered instance" do
    sap_system_id = UUID.uuid4()
    host_id = UUID.uuid4()

    Repo.insert!(%OperationSchedule{
      target_type: "sap_system",
      target_id: sap_system_id,
      operation: "sap_instance_start",
      params: %{"host_id" => host_id, "instance_number" => "10"},
      starts_at: ~U[2026-11-07 02:00:00.000000Z],
      timezone: "Etc/UTC",
      next_run_at: ~U[2026-11-07 02:00:00.000000Z]
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

    assert [] == Repo.all(OperationSchedule)
  end

  test "should handle the deregistration of every target type" do
    for event <- [
          %ClusterDeregistered{cluster_id: UUID.uuid4(), deregistered_at: DateTime.utc_now()},
          %SapSystemDeregistered{
            sap_system_id: UUID.uuid4(),
            deregistered_at: DateTime.utc_now()
          },
          %DatabaseDeregistered{database_id: UUID.uuid4(), deregistered_at: DateTime.utc_now()},
          %ApplicationInstanceDeregistered{
            sap_system_id: UUID.uuid4(),
            host_id: UUID.uuid4(),
            instance_number: "00",
            deregistered_at: DateTime.utc_now()
          }
        ] do
      assert :ok == OperationSchedulesCleanupEventHandler.handle(event, %{})
    end
  end
end
