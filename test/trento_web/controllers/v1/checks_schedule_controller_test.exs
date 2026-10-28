# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule TrentoWeb.V1.ChecksScheduleControllerTest do
  use TrentoWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import Trento.Factory
  import Trento.Support.Helpers.AbilitiesTestHelper

  setup_all :setup_api_spec_v1
  setup :setup_user

  setup do
    previous = Application.get_env(:trento, :checks_execution)
    on_exit(fn -> Application.put_env(:trento, :checks_execution, previous) end)
    Application.put_env(:trento, :checks_execution, interval: nil)
  end

  defp put_schedule(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(path, body)
  end

  test "should return the checks schedule of a host", %{conn: conn, api_spec: api_spec} do
    %{id: host_id} = insert(:host)

    assert %{interval: nil, effective_interval: "5m"} =
             conn
             |> get("/api/v1/hosts/#{host_id}/checks/schedule")
             |> json_response(200)
             |> assert_schema("ChecksScheduleV1", api_spec)
  end

  test "should change the checks schedule of a host and a cluster", %{
    conn: conn,
    api_spec: api_spec
  } do
    %{id: host_id} = insert(:host)
    %{id: cluster_id} = insert(:cluster)

    assert %{interval: "6h", effective_interval: "6h"} =
             conn
             |> put_schedule("/api/v1/hosts/#{host_id}/checks/schedule", %{
               interval: "6h"
             })
             |> json_response(200)
             |> assert_schema("ChecksScheduleV1", api_spec)

    assert %{interval: "disabled", next_execution_at: nil} =
             conn
             |> put_schedule("/api/v1/clusters/#{cluster_id}/checks/schedule", %{
               interval: "disabled"
             })
             |> json_response(200)
             |> assert_schema("ChecksScheduleV1", api_spec)
  end

  test "should set and remove the exception window of a host", %{
    conn: conn,
    api_spec: api_spec
  } do
    %{id: host_id} = insert(:host)

    window = %{
      starts_at: DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.to_iso8601(),
      timezone: "Europe/Berlin",
      duration_minutes: 60,
      recurrence: %{frequency: "weekly", interval: 1, weekdays: [6, 7]}
    }

    assert %{exception_window: %{duration_minutes: 60}, in_exception_window: false} =
             conn
             |> put_schedule("/api/v1/hosts/#{host_id}/checks/schedule", %{
               interval: "6h",
               exception_window: window
             })
             |> json_response(200)
             |> assert_schema("ChecksScheduleV1", api_spec)

    assert %{exception_window: nil} =
             conn
             |> put_schedule("/api/v1/hosts/#{host_id}/checks/schedule", %{
               interval: "6h",
               exception_window: nil
             })
             |> json_response(200)
             |> assert_schema("ChecksScheduleV1", api_spec)
  end

  test "should refuse a manual checks execution during the exception window", %{
    conn: conn,
    api_spec: api_spec
  } do
    %{id: host_id} = insert(:host, selected_checks: ["check_1"])

    conn
    |> put_schedule("/api/v1/hosts/#{host_id}/checks/schedule", %{
      interval: nil,
      exception_window: %{
        starts_at: DateTime.utc_now() |> DateTime.add(-10, :minute) |> DateTime.to_iso8601(),
        timezone: "Etc/UTC",
        duration_minutes: 60,
        recurrence: nil
      }
    })
    |> json_response(200)

    assert %{errors: [%{detail: "Checks cannot be executed during exception window"}]} =
             conn
             |> post("/api/v1/hosts/#{host_id}/checks/request_execution")
             |> json_response(422)
             |> assert_schema("UnprocessableEntityV1", api_spec)
  end

  test "should log the change of the interval of a host and a cluster", %{conn: conn} do
    %{id: host_id, hostname: hostname} = insert(:host)
    %{id: cluster_id, name: cluster_name} = insert(:cluster)

    conn
    |> put_schedule("/api/v1/hosts/#{host_id}/checks/schedule", %{interval: "6h"})
    |> json_response(200)

    conn
    |> put_schedule("/api/v1/clusters/#{cluster_id}/checks/schedule", %{interval: nil})
    |> json_response(200)

    wait_for_tasks_completion()

    assert %Trento.ActivityLog.ActivityLog{
             metadata: %{"host_id" => ^host_id, "hostname" => ^hostname, "interval" => "6h"}
           } =
             Trento.Repo.get_by!(Trento.ActivityLog.ActivityLog,
               type: "host_checks_frequency_changed"
             )

    assert %Trento.ActivityLog.ActivityLog{
             metadata: %{"cluster_id" => ^cluster_id, "name" => ^cluster_name, "interval" => nil}
           } =
             Trento.Repo.get_by!(Trento.ActivityLog.ActivityLog,
               type: "cluster_checks_frequency_changed"
             )
  end

  test "should refuse invalid settings", %{conn: conn, api_spec: api_spec} do
    %{id: host_id} = insert(:host)

    conn
    |> put_schedule("/api/v1/hosts/#{host_id}/checks/schedule", %{
      interval: "7m"
    })
    |> json_response(422)
    |> assert_schema("UnprocessableEntityV1", api_spec)
  end

  test "should not find an unknown target", %{conn: conn, api_spec: api_spec} do
    for path <- ["/api/v1/clusters/#{UUID.uuid4()}", "/api/v1/hosts/#{UUID.uuid4()}"] do
      conn
      |> get("#{path}/checks/schedule")
      |> json_response(404)
      |> assert_schema("NotFoundV1", api_spec)
    end
  end

  test "should require the check frequency ability to change the interval", %{
    conn: conn,
    api_spec: api_spec
  } do
    %{id: host_id} = insert(:host)
    %{id: cluster_id} = insert(:cluster)

    %{id: unprivileged_id} =
      insert(:user, abilities: [%{name: "all", resource: "host_checks_selection"}])

    unprivileged =
      Pow.Plug.assign_current_user(
        conn,
        %{"user_id" => unprivileged_id},
        Pow.Plug.fetch_config(conn)
      )

    for path <- ["/api/v1/hosts/#{host_id}", "/api/v1/clusters/#{cluster_id}"] do
      unprivileged
      |> put_schedule("#{path}/checks/schedule", %{interval: "6h"})
      |> json_response(403)
      |> assert_schema("ForbiddenV1", api_spec)

      unprivileged
      |> get("#{path}/checks/schedule")
      |> json_response(200)
    end
  end
end
