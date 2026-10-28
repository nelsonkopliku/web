# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule TrentoWeb.V1.MaintenanceWindowControllerTest do
  use TrentoWeb.ConnCase
  use Trento.EventStoreCase
  use Trento.CommandedCase

  import OpenApiSpex.TestAssertions
  import Trento.Factory
  import Trento.Support.Helpers.AbilitiesTestHelper

  # The answers come from the read model, projected from the events
  @moduletag mocked_commanded: false

  setup_all :setup_api_spec_v1

  # The event store case puts its own conn in the context
  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  setup :setup_user

  defp in_days(days),
    do: DateTime.utc_now() |> DateTime.add(days, :day) |> DateTime.truncate(:second)

  defp body(target_type, target_id, overrides \\ %{}) do
    Map.merge(
      %{
        target_type: target_type,
        target_id: target_id,
        starts_at: DateTime.to_iso8601(in_days(2)),
        timezone: "Europe/Berlin",
        duration_minutes: 120,
        recurrence: nil,
        forbids: ["checks_execution", "operations"]
      },
      overrides
    )
  end

  defp post_window(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/v1/maintenance_windows", body)
  end

  defp unprivileged(conn) do
    %{id: user_id} = insert(:user)
    Pow.Plug.assign_current_user(conn, %{"user_id" => user_id}, Pow.Plug.fetch_config(conn))
  end

  test "should schedule a maintenance window", %{conn: conn, api_spec: api_spec} do
    %{id: cluster_id, name: name} = insert(:cluster)

    assert %{
             target_id: ^cluster_id,
             target_name: ^name,
             inherited: false,
             active: false,
             forbids: ["checks_execution", "operations"],
             next_occurrence: %{starts_at: _}
           } =
             conn
             |> post_window(
               body("cluster", cluster_id, %{recurrence: %{frequency: "weekly", interval: 1}})
             )
             |> json_response(201)
             |> assert_schema("MaintenanceWindowV1", api_spec)
  end

  test "should list the windows of a target and those it inherits", %{
    conn: conn,
    api_spec: api_spec
  } do
    %{id: cluster_id} = insert(:cluster)
    %{id: host_id} = insert(:host, cluster_id: cluster_id)
    %{"id" => window_id} = conn |> post_window(body("cluster", cluster_id)) |> json_response(201)

    assert [%{id: ^window_id, inherited: true}] =
             conn
             |> get("/api/v1/maintenance_windows?target_type=host&target_id=#{host_id}")
             |> json_response(200)
             |> assert_schema("MaintenanceWindowCollectionV1", api_spec)
  end

  test "should change and delete a window", %{conn: conn, api_spec: api_spec} do
    %{id: host_id} = insert(:host)
    %{"id" => window_id} = conn |> post_window(body("host", host_id)) |> json_response(201)

    assert %{id: ^window_id, forbids: ["operations"], duration_minutes: 30} =
             conn
             |> put_req_header("content-type", "application/json")
             |> put("/api/v1/maintenance_windows/#{window_id}", %{
               starts_at: DateTime.to_iso8601(in_days(3)),
               timezone: "Etc/UTC",
               duration_minutes: 30,
               recurrence: nil,
               forbids: ["operations"]
             })
             |> json_response(200)
             |> assert_schema("MaintenanceWindowV1", api_spec)

    conn
    |> delete("/api/v1/maintenance_windows/#{window_id}")
    |> response(204)

    conn
    |> delete("/api/v1/maintenance_windows/#{window_id}")
    |> json_response(404)
    |> assert_schema("NotFoundV1", api_spec)
  end

  test "should refuse an invalid window and an unknown target", %{conn: conn, api_spec: api_spec} do
    %{id: host_id} = insert(:host)

    for body <- [
          body("host", host_id, %{forbids: []}),
          body("host", host_id, %{starts_at: DateTime.to_iso8601(in_days(-1))}),
          body("host", host_id, %{
            recurrence: %{frequency: "daily", interval: 1, max_occurrences: 2}
          })
        ] do
      conn
      |> post_window(body)
      |> json_response(422)
      |> assert_schema("UnprocessableEntityV1", api_spec)
    end

    conn
    |> post_window(body("host", UUID.uuid4()))
    |> json_response(404)
    |> assert_schema("NotFoundV1", api_spec)
  end

  test "should schedule a window on several targets", %{conn: conn, api_spec: api_spec} do
    [%{id: first}, %{id: second}] = insert_list(2, :host)

    request =
      body("host", nil)
      |> Map.delete(:target_id)
      |> Map.put(:target_ids, [first, second])

    assert %{bulk_id: bulk_id, maintenance_windows: [%{target_id: ^first}, %{target_id: ^second}]} =
             conn
             |> put_req_header("content-type", "application/json")
             |> post("/api/v1/maintenance_windows/bulk", request)
             |> json_response(201)
             |> assert_schema("BulkMaintenanceWindowsV1", api_spec)

    assert is_binary(bulk_id)

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/v1/maintenance_windows/bulk", Map.put(request, :target_ids, []))
    |> json_response(422)
    |> assert_schema("UnprocessableEntityV1", api_spec)
  end

  test "should require the maintenance windows ability to change windows", %{
    conn: conn,
    api_spec: api_spec
  } do
    %{id: host_id} = insert(:host)
    %{"id" => window_id} = conn |> post_window(body("host", host_id)) |> json_response(201)
    conn = unprivileged(conn)

    conn
    |> post_window(body("host", host_id))
    |> json_response(403)
    |> assert_schema("ForbiddenV1", api_spec)

    conn
    |> delete("/api/v1/maintenance_windows/#{window_id}")
    |> json_response(403)
    |> assert_schema("ForbiddenV1", api_spec)

    conn
    |> get("/api/v1/maintenance_windows?target_type=host&target_id=#{host_id}")
    |> json_response(200)
  end
end
