# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule TrentoWeb.V1.OperationScheduleControllerTest do
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

  defp body(host_id, overrides \\ %{}) do
    Map.merge(
      %{
        target_type: "host",
        target_id: host_id,
        operation: "reboot",
        params: %{},
        starts_at: DateTime.to_iso8601(in_days(3)),
        timezone: "Europe/Berlin",
        recurrence: nil
      },
      overrides
    )
  end

  defp post_schedule(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/v1/operation_schedules", body)
  end

  defp unprivileged(conn) do
    %{id: user_id} = insert(:user)
    Pow.Plug.assign_current_user(conn, %{"user_id" => user_id}, Pow.Plug.fetch_config(conn))
  end

  describe "create" do
    test "should schedule an operation", %{conn: conn, api_spec: api_spec} do
      %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)

      conn
      |> post_schedule(body(host_id, %{recurrence: %{frequency: "daily", interval: 2}}))
      |> json_response(201)
      |> assert_schema("OperationScheduleV1", api_spec)
      |> then(fn schedule ->
        assert %{target_id: ^host_id, operation: "reboot", warnings: []} = schedule
        assert %{frequency: "daily", interval: 2} = schedule.recurrence
      end)
    end

    test "should return the policies that fail now as warnings", %{
      conn: conn,
      api_spec: api_spec
    } do
      %{id: host_id} = insert(:host, heartbeat: :critical, cluster_id: nil)

      assert %{warnings: [%{message: "Trento agent is not currently running in the host"}]} =
               conn
               |> post_schedule(body(host_id))
               |> json_response(201)
               |> assert_schema("OperationScheduleV1", api_spec)
    end

    test "should refuse a schedule that is not valid", %{conn: conn, api_spec: api_spec} do
      %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)

      for body <- [
            body(host_id, %{operation: "saptune_solution_apply"}),
            body(host_id, %{starts_at: DateTime.to_iso8601(in_days(-1))}),
            body(host_id, %{target_type: "cluster"})
          ] do
        conn
        |> post_schedule(body)
        |> json_response(422)
        |> assert_schema("UnprocessableEntityV1", api_spec)
      end
    end

    test "should refuse params that the immediate request of the operation refuses", %{
      conn: conn,
      api_spec: api_spec
    } do
      %{id: cluster_id} = insert(:cluster)
      %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)
      %{id: sap_system_id} = insert(:sap_system)

      for body <- [
            body(host_id, %{params: %{unexpected: true}}),
            body(cluster_id, %{
              target_type: "cluster",
              operation: "cluster_maintenance_change",
              params: %{}
            }),
            body(sap_system_id, %{
              target_type: "sap_system",
              operation: "sap_instance_stop",
              params: %{timeout: 300}
            })
          ] do
        assert %{errors: [%{source: %{pointer: "/params" <> _}} | _]} =
                 conn
                 |> post_schedule(body)
                 |> json_response(422)
                 |> assert_schema("UnprocessableEntityV1", api_spec)
      end
    end

    @tag mocked_commanded: true
    test "should accept a schedule saved while its read model is late", %{conn: conn} do
      %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)

      Mox.expect(Trento.Commanded.Mock, :dispatch, fn _, _ ->
        {:error, :consistency_timeout}
      end)

      assert %{} == conn |> post_schedule(body(host_id)) |> json_response(202)
    end

    test "should not find an unknown target", %{conn: conn, api_spec: api_spec} do
      conn
      |> post_schedule(body(UUID.uuid4()))
      |> json_response(404)
      |> assert_schema("NotFoundV1", api_spec)
    end

    test "should refuse a user without the ability of the operation", %{
      conn: conn,
      api_spec: api_spec
    } do
      %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)

      conn
      |> unprivileged()
      |> post_schedule(body(host_id))
      |> json_response(403)
      |> assert_schema("ForbiddenV1", api_spec)
    end
  end

  describe "bulk" do
    defp bulk(conn, body) do
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/operation_schedules/bulk", body)
    end

    defp bulk_body(target_ids) do
      %{
        target_type: "host",
        target_ids: target_ids,
        operation: "reboot",
        params: %{},
        starts_at: DateTime.to_iso8601(in_days(3)),
        timezone: "Etc/UTC",
        recurrence: nil
      }
    end

    test "should schedule an operation on several targets", %{conn: conn, api_spec: api_spec} do
      %{id: first} = insert(:host, heartbeat: :passing, cluster_id: nil)
      %{id: second} = insert(:host, heartbeat: :critical, cluster_id: nil)

      assert %{bulk_id: bulk_id, schedules: [first_schedule, second_schedule]} =
               conn
               |> bulk(bulk_body([first, second]))
               |> json_response(201)
               |> assert_schema("BulkOperationSchedulesV1", api_spec)

      assert %{target_id: ^first, bulk_id: ^bulk_id, warnings: []} = first_schedule
      assert %{target_id: ^second, bulk_id: ^bulk_id, warnings: [_]} = second_schedule
    end

    test "should not find unknown targets", %{conn: conn, api_spec: api_spec} do
      %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)

      conn
      |> bulk(bulk_body([host_id, UUID.uuid4()]))
      |> json_response(404)
      |> assert_schema("NotFoundV1", api_spec)
    end

    test "should refuse an empty selection, wrong params and a user without the ability", %{
      conn: conn,
      api_spec: api_spec
    } do
      %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)

      for body <- [bulk_body([]), Map.put(bulk_body([host_id]), :params, %{unexpected: true})] do
        conn
        |> bulk(body)
        |> json_response(422)
        |> assert_schema("UnprocessableEntityV1", api_spec)
      end

      conn
      |> unprivileged()
      |> bulk(bulk_body([host_id]))
      |> json_response(403)
      |> assert_schema("ForbiddenV1", api_spec)
    end
  end

  describe "list, change and cancel" do
    setup %{conn: conn} do
      %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)
      %{"id" => schedule_id} = conn |> post_schedule(body(host_id)) |> json_response(201)
      %{host_id: host_id, schedule_id: schedule_id}
    end

    test "should list the schedules of a target", %{
      conn: conn,
      api_spec: api_spec,
      host_id: host_id,
      schedule_id: schedule_id
    } do
      assert [%{id: ^schedule_id}] =
               conn
               |> get("/api/v1/operation_schedules?target_id=#{host_id}")
               |> json_response(200)
               |> assert_schema("OperationScheduleCollectionV1", api_spec)
    end

    test "should list the schedules of an operation on several targets", %{
      conn: conn,
      api_spec: api_spec,
      host_id: host_id,
      schedule_id: schedule_id
    } do
      other_host_id = UUID.uuid4()

      assert [%{id: ^schedule_id}] =
               conn
               |> get(
                 "/api/v1/operation_schedules?target_ids=#{host_id},#{other_host_id}&operation=reboot"
               )
               |> json_response(200)
               |> assert_schema("OperationScheduleCollectionV1", api_spec)

      conn
      |> get("/api/v1/operation_schedules")
      |> json_response(422)
      |> assert_schema("UnprocessableEntityV1", api_spec)
    end

    test "should change a schedule", %{conn: conn, api_spec: api_spec, schedule_id: schedule_id} do
      starts_at = in_days(5)

      assert %{id: ^schedule_id, recurrence: nil, warnings: []} =
               conn
               |> put_req_header("content-type", "application/json")
               |> put("/api/v1/operation_schedules/#{schedule_id}", %{
                 starts_at: DateTime.to_iso8601(starts_at),
                 timezone: "Etc/UTC"
               })
               |> json_response(200)
               |> assert_schema("OperationScheduleV1", api_spec)
    end

    test "should cancel a schedule", %{conn: conn, host_id: host_id, schedule_id: schedule_id} do
      conn
      |> delete("/api/v1/operation_schedules/#{schedule_id}")
      |> response(204)

      assert [] ==
               conn
               |> get("/api/v1/operation_schedules?target_id=#{host_id}")
               |> json_response(200)
    end

    test "should not find an unknown schedule", %{conn: conn, api_spec: api_spec} do
      conn
      |> delete("/api/v1/operation_schedules/#{UUID.uuid4()}")
      |> json_response(404)
      |> assert_schema("NotFoundV1", api_spec)

      conn
      |> put_req_header("content-type", "application/json")
      |> put("/api/v1/operation_schedules/#{UUID.uuid4()}", %{
        starts_at: DateTime.to_iso8601(in_days(5)),
        timezone: "Etc/UTC"
      })
      |> json_response(404)
      |> assert_schema("NotFoundV1", api_spec)
    end

    test "should refuse a change or a cancel from a user without the ability", %{
      conn: conn,
      api_spec: api_spec,
      schedule_id: schedule_id
    } do
      conn = unprivileged(conn)

      conn
      |> delete("/api/v1/operation_schedules/#{schedule_id}")
      |> json_response(403)
      |> assert_schema("ForbiddenV1", api_spec)

      conn
      |> put_req_header("content-type", "application/json")
      |> put("/api/v1/operation_schedules/#{schedule_id}", %{
        starts_at: DateTime.to_iso8601(in_days(5)),
        timezone: "Etc/UTC"
      })
      |> json_response(403)
      |> assert_schema("ForbiddenV1", api_spec)
    end
  end
end
