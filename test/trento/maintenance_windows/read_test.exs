# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.ReadTest do
  use ExUnit.Case
  use Trento.EventStoreCase
  use Trento.CommandedCase

  import Mox
  import Trento.Factory

  alias Trento.MaintenanceWindows
  alias Trento.MaintenanceWindows.Projections.MaintenanceWindowReadModel, as: MaintenanceWindow
  alias Trento.Support.DateService

  # The windows are aggregates, read back from their read model
  @moduletag mocked_commanded: false

  @created_at ~U[2026-11-02 10:00:00.000000Z]

  setup do
    %{id: cluster_id, name: cluster_name} = insert(:cluster, name: "hana_cluster")
    %{id: host_id} = insert(:host, cluster_id: cluster_id)
    %{cluster_id: cluster_id, cluster_name: cluster_name, host_id: host_id}
  end

  defp window!(target_type, target_id, starts_at, overrides \\ %{}) do
    stub(DateService.Mock, :utc_now, fn -> @created_at end)

    {:ok, window} =
      MaintenanceWindows.create_window(
        Map.merge(
          %{
            target_type: target_type,
            target_id: target_id,
            starts_at: starts_at,
            timezone: "Etc/UTC",
            duration_minutes: 60,
            forbids: ["operations"]
          },
          overrides
        ),
        "admin",
        DateService.Mock
      )

    window
  end

  defp list_at(target_type, target_id, now) do
    stub(DateService.Mock, :utc_now, fn -> now end)
    MaintenanceWindows.list_covering_windows(target_type, target_id, DateService.Mock)
  end

  test "should list the windows of a target and those it inherits", %{
    cluster_id: cluster_id,
    cluster_name: cluster_name,
    host_id: host_id
  } do
    %{id: own} = window!("host", host_id, ~U[2026-11-05 02:00:00.000000Z])
    %{id: inherited} = window!("cluster", cluster_id, ~U[2026-11-04 02:00:00.000000Z])

    assert [
             %{
               window: %MaintenanceWindow{id: ^inherited},
               inherited: true,
               target_name: ^cluster_name,
               active: false,
               current_occurrence: nil,
               next_occurrence: %{
                 starts_at: ~U[2026-11-04 02:00:00.000000Z],
                 ends_at: ~U[2026-11-04 03:00:00.000000Z]
               }
             },
             %{window: %MaintenanceWindow{id: ^own}, inherited: false}
           ] = list_at("host", host_id, @created_at)

    assert [%{window: %MaintenanceWindow{id: ^inherited}, inherited: false}] =
             list_at("cluster", cluster_id, @created_at)
  end

  test "should list the active windows first and leave out the ended ones", %{
    cluster_id: cluster_id,
    host_id: host_id
  } do
    %{id: active} = window!("cluster", cluster_id, ~U[2026-11-04 02:00:00.000000Z])

    %{id: upcoming} = window!("host", host_id, ~U[2026-11-05 01:00:00.000000Z])
    window!("host", host_id, ~U[2026-11-03 02:00:00.000000Z])

    assert [
             %{
               window: %MaintenanceWindow{id: ^active},
               active: true,
               current_occurrence: %{ends_at: ~U[2026-11-04 03:00:00.000000Z]},
               next_occurrence: nil
             },
             %{window: %MaintenanceWindow{id: ^upcoming}, active: false}
           ] = list_at("host", host_id, ~U[2026-11-04 02:30:00.000000Z])
  end

  test "should tell the current and next occurrences of a periodic window", %{host_id: host_id} do
    window!("host", host_id, ~U[2026-11-04 02:00:00.000000Z], %{
      recurrence: %{frequency: "daily", interval: 1}
    })

    assert [
             %{
               active: true,
               current_occurrence: %{starts_at: ~U[2026-11-06 02:00:00.000000Z]},
               next_occurrence: %{starts_at: ~U[2026-11-07 02:00:00.000000Z]}
             }
           ] = list_at("host", host_id, ~U[2026-11-06 02:10:00.000000Z])
  end

  test "should get a window by id", %{host_id: host_id} do
    %{id: window_id} = window!("host", host_id, ~U[2026-11-05 02:00:00.000000Z])

    assert {:ok, %MaintenanceWindow{id: ^window_id}} = MaintenanceWindows.get_window(window_id)
    assert {:error, :not_found} == MaintenanceWindows.get_window(UUID.uuid4())
  end
end
