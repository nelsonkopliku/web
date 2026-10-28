# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.ChecksTest do
  use ExUnit.Case
  use Trento.EventStoreCase
  use Trento.CommandedCase

  import Mox
  import Trento.Factory

  alias Trento.ChecksScheduling
  alias Trento.Infrastructure.Messaging.Adapter.Mock, as: Messaging
  alias Trento.MaintenanceWindows
  alias Trento.Support.DateService

  # The windows are aggregates, read back from their read model
  @moduletag mocked_commanded: false

  setup :verify_on_exit!

  @created_at ~U[2026-11-02 10:00:00.000000Z]
  @during ~U[2026-11-04 02:30:00.000000Z]

  setup do
    previous = Application.get_env(:trento, :checks_execution)
    on_exit(fn -> Application.put_env(:trento, :checks_execution, previous) end)
    Application.put_env(:trento, :checks_execution, interval: nil)

    %{id: cluster_id} = insert(:cluster)
    %{id: host_id} = insert(:host, cluster_id: cluster_id, selected_checks: ["check_1"])
    %{cluster_id: cluster_id, host_id: host_id}
  end

  defp window!(target_type, target_id, starts_at, forbids, duration \\ 60) do
    stub(DateService.Mock, :utc_now, fn -> @created_at end)

    {:ok, window} =
      MaintenanceWindows.create_window(
        %{
          target_type: target_type,
          target_id: target_id,
          starts_at: starts_at,
          timezone: "Etc/UTC",
          duration_minutes: duration,
          forbids: forbids
        },
        "admin",
        DateService.Mock
      )

    window
  end

  defp requested(now) do
    test_pid = self()

    stub(Messaging, :publish, fn _, "executions", %{group_id: group_id} ->
      send(test_pid, {:requested, group_id})
      :ok
    end)

    stub(DateService.Mock, :utc_now, fn -> now end)
    ChecksScheduling.request_due_executions(DateService.Mock)
    collect([])
  end

  defp collect(acc) do
    receive do
      {:requested, id} -> collect([id | acc])
    after
      0 -> acc
    end
  end

  test "should not execute the checks of a target covered by a window that forbids them", %{
    cluster_id: cluster_id,
    host_id: host_id
  } do
    window!("cluster", cluster_id, ~U[2026-11-04 02:00:00.000000Z], ["checks_execution"])

    refute host_id in requested(@during)
    assert host_id in requested(~U[2026-11-04 03:00:00.000000Z])
  end

  test "should execute the checks during a window that only forbids operations", %{
    cluster_id: cluster_id,
    host_id: host_id
  } do
    window!("cluster", cluster_id, ~U[2026-11-04 02:00:00.000000Z], ["operations"])

    assert host_id in requested(@during)
  end

  test "should plan the next execution after a chain of windows", %{
    cluster_id: cluster_id,
    host_id: host_id
  } do
    window!("cluster", cluster_id, ~U[2026-11-04 02:00:00.000000Z], ["checks_execution"])
    window!("host", host_id, ~U[2026-11-04 02:45:00.000000Z], ["checks_execution"], 60)

    assert ~U[2026-11-04 03:45:00.000000Z] ==
             MaintenanceWindows.forbidden_until("host", host_id, :checks_execution, @during)

    assert nil ==
             MaintenanceWindows.forbidden_until("host", host_id, :operations, @during)

    stub(DateService.Mock, :utc_now, fn -> @during end)

    assert {:ok, %{next_execution_at: ~U[2026-11-04 03:45:00.000000Z]}} =
             ChecksScheduling.get_target_schedule(:host, host_id, DateService.Mock)
  end

  test "should tell the ongoing window that forbids an action", %{
    cluster_id: cluster_id,
    host_id: host_id
  } do
    %{id: window_id} =
      window!("cluster", cluster_id, ~U[2026-11-04 02:00:00.000000Z], ["checks_execution"])

    stub(DateService.Mock, :utc_now, fn -> @during end)

    assert {:ok, %{id: ^window_id}, _name, ~U[2026-11-04 03:00:00.000000Z]} =
             MaintenanceWindows.forbidding_window(
               "host",
               host_id,
               :checks_execution,
               DateService.Mock
             )

    assert :none ==
             MaintenanceWindows.forbidding_window("host", host_id, :operations, DateService.Mock)
  end
end
