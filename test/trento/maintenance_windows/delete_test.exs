# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.DeleteTest do
  use ExUnit.Case
  use Trento.EventStoreCase
  use Trento.CommandedCase

  import Mox
  import Trento.Factory

  alias Trento.ActivityLog.ActivityLog
  alias Trento.Clusters.Events.ClusterDeregistered
  alias Trento.Databases.Events.DatabaseDeregistered
  alias Trento.Hosts.Events.HostDeregistered
  alias Trento.Infrastructure.Commanded.EventHandlers.MaintenanceWindowsCleanupEventHandler
  alias Trento.MaintenanceWindows
  alias Trento.MaintenanceWindows.Projections.MaintenanceWindowReadModel, as: MaintenanceWindow
  alias Trento.Repo
  alias Trento.SapSystems.Events.SapSystemDeregistered
  alias Trento.Support.DateService

  # The windows are aggregates, read back from their read model
  @moduletag mocked_commanded: false

  setup do
    stub(DateService.Mock, :utc_now, fn -> ~U[2026-11-02 10:00:00.000000Z] end)
    :ok
  end

  defp window!(target_type, target_id) do
    {:ok, window} =
      MaintenanceWindows.create_window(
        %{
          target_type: target_type,
          target_id: target_id,
          starts_at: ~U[2026-11-04 02:00:00.000000Z],
          timezone: "Etc/UTC",
          duration_minutes: 60,
          forbids: ["operations"]
        },
        "admin",
        DateService.Mock
      )

    window
  end

  test "should delete a window and log it" do
    %{id: host_id} = insert(:host)
    %{id: window_id} = window!("host", host_id)

    assert :ok == MaintenanceWindows.delete_window(window_id, "operator")
    assert {:error, :not_found} == MaintenanceWindows.delete_window(window_id, "operator")
    assert {:error, :not_found} == MaintenanceWindows.get_window(window_id)

    assert %ActivityLog{actor: "operator", metadata: %{"correlation_id" => ^window_id}} =
             Repo.get_by!(ActivityLog, type: "maintenance_window_deleted")
  end

  test "should delete the windows of a deregistered target, correlated to the clean up" do
    %{id: host_id} = insert(:host)
    %{id: cluster_id} = insert(:cluster)
    %{id: database_id} = insert(:database)
    %{id: sap_system_id} = insert(:sap_system)
    %{id: kept_host_id} = insert(:host)

    window!("host", host_id)
    window!("cluster", cluster_id)
    window!("database", database_id)
    window!("sap_system", sap_system_id)
    %{id: kept} = window!("host", kept_host_id)
    cleanup_correlation_id = UUID.uuid4()
    now = DateTime.utc_now()

    for event <- [
          %HostDeregistered{host_id: host_id, deregistered_at: now},
          %ClusterDeregistered{cluster_id: cluster_id, deregistered_at: now},
          %DatabaseDeregistered{database_id: database_id, deregistered_at: now},
          %SapSystemDeregistered{sap_system_id: sap_system_id, deregistered_at: now}
        ] do
      assert :ok ==
               MaintenanceWindowsCleanupEventHandler.handle(event, %{
                 correlation_id: cleanup_correlation_id
               })
    end

    assert [%MaintenanceWindow{id: ^kept}] = Repo.all(MaintenanceWindow)

    deleted =
      ActivityLog
      |> Repo.all()
      |> Enum.filter(&(&1.type == "maintenance_window_deleted"))

    assert 4 == length(deleted)

    assert Enum.all?(
             deleted,
             &match?(
               %ActivityLog{
                 actor: "system",
                 metadata: %{"correlation_id" => ^cleanup_correlation_id}
               },
               &1
             )
           )
  end

  test "should skip the windows deleted meanwhile when cleaning up" do
    %{id: host_id} = insert(:host)
    %{id: window_id} = window!("host", host_id)
    :ok = MaintenanceWindows.delete_window(window_id, "operator")

    # the read model still shows the window to the clean up
    insert(:maintenance_window, id: window_id, target_id: host_id)

    assert :ok ==
             MaintenanceWindowsCleanupEventHandler.handle(
               %HostDeregistered{host_id: host_id, deregistered_at: DateTime.utc_now()},
               %{correlation_id: UUID.uuid4()}
             )

    assert [_] =
             Enum.filter(Repo.all(ActivityLog), &(&1.type == "maintenance_window_deleted"))
  end

  @tag mocked_commanded: true
  test "should return the error of a window that cannot be deleted, so that it is retried" do
    %{id: host_id} = insert(:host)
    insert(:maintenance_window, target_id: host_id)

    Mox.expect(Trento.Commanded.Mock, :dispatch, fn _, _ ->
      {:error, :event_store_unavailable}
    end)

    assert {:error, :event_store_unavailable} ==
             MaintenanceWindowsCleanupEventHandler.handle(
               %HostDeregistered{host_id: host_id, deregistered_at: DateTime.utc_now()},
               %{}
             )
  end
end
