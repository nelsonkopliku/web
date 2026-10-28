# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.SchedulesCreateTest do
  use ExUnit.Case
  use Trento.EventStoreCase
  use Trento.CommandedCase

  import Mox
  import Trento.Factory

  alias Trento.ActivityLog.ActivityLog
  alias Trento.Operations.Projections.OperationScheduleReadModel
  alias Trento.Operations.Schedules
  alias Trento.Repo
  alias Trento.Support.DateService

  @moduletag mocked_commanded: false

  setup :verify_on_exit!

  @now ~U[2026-11-02 10:00:00.000000Z]

  setup do
    stub(DateService.Mock, :utc_now, fn -> @now end)
    %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)
    %{host_id: host_id}
  end

  defp attrs(host_id, overrides \\ %{}) do
    Map.merge(
      %{
        target_type: "host",
        target_id: host_id,
        operation: "reboot",
        params: %{},
        starts_at: ~U[2026-11-07 02:00:00.000000Z],
        timezone: "Europe/Berlin",
        recurrence: nil
      },
      overrides
    )
  end

  test "should schedule a one-time operation", %{host_id: host_id} do
    assert {:ok, %OperationScheduleReadModel{} = schedule, []} =
             Schedules.create_schedule(attrs(host_id), "admin", DateService.Mock)

    assert %OperationScheduleReadModel{
             target_type: "host",
             target_id: ^host_id,
             operation: "reboot",
             frequency: nil,
             next_run_at: ~U[2026-11-07 02:00:00.000000Z],
             occurrences: 0,
             created_by: "admin"
           } = schedule
  end

  test "should schedule a periodic operation on its first occurrence", %{host_id: host_id} do
    # Saturday 7 November 2026, 03:00 in Berlin; the schedule runs on Mondays
    attrs =
      attrs(host_id, %{
        recurrence: %{frequency: "weekly", interval: 1, weekdays: [1], max_occurrences: 3}
      })

    assert {:ok, schedule, []} = Schedules.create_schedule(attrs, "admin", DateService.Mock)

    assert %OperationScheduleReadModel{
             frequency: :weekly,
             interval: 1,
             weekdays: [1],
             max_occurrences: 3,
             next_run_at: ~U[2026-11-09 02:00:00.000000Z]
           } = schedule
  end

  test "should save a schedule whose policies fail now and return them as warnings" do
    %{id: host_id} = insert(:host, heartbeat: :critical, cluster_id: nil)

    assert {:ok, %OperationScheduleReadModel{}, [%{message: message}]} =
             Schedules.create_schedule(attrs(host_id), "admin", DateService.Mock)

    assert message == "Trento agent is not currently running in the host"
  end

  test "should log the schedule in the activity log and tell the UI", %{host_id: host_id} do
    TrentoWeb.Endpoint.subscribe("monitoring:operation_schedules")
    %{hostname: hostname} = Repo.get!(Trento.Hosts.Projections.HostReadModel, host_id)

    {:ok, %{id: schedule_id}, _} =
      Schedules.create_schedule(attrs(host_id), "admin", DateService.Mock)

    assert [
             %ActivityLog{
               type: "operation_scheduled",
               actor: "admin",
               severity: 9,
               metadata: %{
                 "schedule_id" => ^schedule_id,
                 "correlation_id" => ^schedule_id,
                 "host_id" => ^host_id,
                 "hostname" => ^hostname,
                 "operation" => "reboot",
                 "next_run_at" => "2026-11-07T02:00:00.000000Z"
               }
             }
           ] = Repo.all(ActivityLog)

    assert_receive %Phoenix.Socket.Broadcast{
      event: "operation_schedules_changed",
      payload: %{target_id: ^host_id}
    }
  end

  test "should not schedule an operation on an unknown target" do
    assert {:error, :not_found} =
             Schedules.create_schedule(attrs(UUID.uuid4()), "admin", DateService.Mock)

    assert [] == Repo.all(OperationScheduleReadModel)
    assert [] == Repo.all(ActivityLog)
  end

  test "should refuse an invalid schedule", %{host_id: host_id} do
    for {overrides, field} <- [
          {%{operation: "saptune_solution_apply"}, :operation},
          {%{target_type: "cluster"}, :operation},
          {%{starts_at: ~U[2026-11-02 09:59:00.000000Z]}, :starts_at},
          {%{timezone: "Mars/Olympus_Mons"}, :timezone},
          {%{recurrence: %{frequency: "hourly", interval: 1}}, :recurrence},
          {%{recurrence: %{frequency: "daily", interval: 0}}, :recurrence},
          {%{recurrence: %{frequency: "weekly", interval: 1, weekdays: [0, 8]}}, :recurrence},
          {%{recurrence: %{frequency: "daily", interval: 1, ends_on: ~D[2026-11-07]}},
           :recurrence}
        ] do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Schedules.create_schedule(attrs(host_id, overrides), "admin", DateService.Mock)

      assert Map.has_key?(Trento.DataCase.errors_on(changeset), field),
             "expected an error on #{field} for #{inspect(overrides)}"
    end

    assert [] == Repo.all(OperationScheduleReadModel)
    assert [] == Repo.all(ActivityLog)
  end

  @tag mocked_commanded: true
  test "should log a schedule that is saved while its read model is late", %{host_id: host_id} do
    expect(Trento.Commanded.Mock, :dispatch, fn _, opts ->
      assert [Trento.Operations.Projections.OperationScheduleProjector] ==
               Keyword.fetch!(opts, :consistency)

      {:error, :consistency_timeout}
    end)

    assert {:error, :consistency_timeout} =
             Schedules.create_schedule(attrs(host_id), "admin", DateService.Mock)

    assert [
             %ActivityLog{
               type: "operation_scheduled",
               actor: "admin",
               metadata: %{"host_id" => ^host_id, "operation" => "reboot", "next_run_at" => nil}
             }
           ] = Repo.all(ActivityLog)
  end
end
