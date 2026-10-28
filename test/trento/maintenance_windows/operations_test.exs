# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.OperationsTest do
  use TrentoWeb.ConnCase, async: true

  import Mox
  import OpenApiSpex.TestAssertions
  import Trento.Factory
  import Trento.Support.Helpers.AbilitiesTestHelper

  alias Trento.ActivityLog.ActivityLog
  alias Trento.Infrastructure.Messaging.Adapter.Mock, as: Messaging
  alias Trento.MaintenanceWindows.MaintenanceWindow
  alias Trento.Operations.{Requests, Scheduler, Schedules}
  alias Trento.Repo
  alias Trento.Support.DateService

  setup_all :setup_api_spec_v1
  setup :setup_user
  setup :verify_on_exit!

  defp ongoing_window!(target_type, target_id, forbids \\ [operations: true]) do
    Repo.insert!(%MaintenanceWindow{
      target_type: target_type,
      target_id: target_id,
      starts_at: DateTime.add(DateTime.utc_now(), -10, :minute),
      timezone: "Etc/UTC",
      duration_minutes: 60,
      forbid_operations: Keyword.get(forbids, :operations, false),
      forbid_checks_execution: Keyword.get(forbids, :checks_execution, false)
    })
  end

  test "should refuse an operation on a target covered by a window that forbids operations" do
    %{id: cluster_id, name: name} = insert(:cluster)
    %{id: host_id} = insert(:host, cluster_id: cluster_id, heartbeat: :passing)
    ongoing_window!("cluster", cluster_id)

    assert {:error, :maintenance_window, [%{message: message, metadata: [%{label: ^name}]}]} =
             Requests.authorize(:host, host_id, :reboot, %{})

    assert message =~ "Operations are not allowed during the maintenance window of {0}"
  end

  test "should let operations run during a window that only forbids checks executions" do
    %{id: host_id} = insert(:host, cluster_id: nil, heartbeat: :passing)
    ongoing_window!("host", host_id, checks_execution: true)

    assert :ok == Requests.authorize(:host, host_id, :reboot, %{})
  end

  test "should refuse a manual operation request during the window", %{
    conn: conn,
    api_spec: api_spec
  } do
    %{id: host_id} = insert(:host, cluster_id: nil, heartbeat: :passing)
    ongoing_window!("host", host_id)
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    assert %{errors: [%{detail: detail}]} =
             conn
             |> put_req_header("content-type", "application/json")
             |> post("/api/v1/hosts/#{host_id}/operations/reboot", %{})
             |> json_response(403)
             |> assert_schema("ForbiddenV1", api_spec)

    assert detail =~ "maintenance window"
  end

  test "should refuse a cluster operation on a host under maintenance", %{conn: conn} do
    %{id: cluster_id} = insert(:cluster)
    %{id: host_id} = insert(:host, cluster_id: cluster_id, heartbeat: :passing)
    ongoing_window!("host", host_id)
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/v1/clusters/#{cluster_id}/hosts/#{host_id}/operations/pacemaker_enable", %{})
    |> json_response(403)
  end

  test "should not request a scheduled operation during the window" do
    %{id: host_id} = insert(:host, cluster_id: nil, heartbeat: :passing)
    starts_at = DateTime.utc_now() |> DateTime.add(1, :minute)
    stub(DateService.Mock, :utc_now, fn -> DateTime.utc_now() end)

    {:ok, schedule, []} =
      Schedules.create_schedule(
        %{
          target_type: "host",
          target_id: host_id,
          operation: "reboot",
          starts_at: starts_at,
          timezone: "Etc/UTC"
        },
        "admin",
        DateService.Mock
      )

    ongoing_window!("host", host_id)
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)
    stub(DateService.Mock, :utc_now, fn -> DateTime.add(starts_at, 30, :second) end)

    run_scheduler(schedule)

    assert %ActivityLog{metadata: %{"reason" => "maintenance_window", "errors" => [_]}} =
             Repo.get_by!(ActivityLog, type: "scheduled_operation_request_failed")
  end

  # The Quantum scheduler runs the due schedules, the Oban one runs the job of
  # an occurrence.
  defp run_scheduler(schedule) do
    Code.ensure_loaded!(Scheduler)

    if function_exported?(Scheduler, :run_due, 1),
      do: Scheduler.run_due(DateService.Mock),
      else: Scheduler.run(schedule.id, schedule.next_run_at, DateService.Mock)
  end
end
