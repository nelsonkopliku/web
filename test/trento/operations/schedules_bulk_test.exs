# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.SchedulesBulkTest do
  use ExUnit.Case
  use Trento.EventStoreCase
  use Trento.CommandedCase

  import Mox
  import Trento.Factory

  alias Trento.ActivityLog.ActivityLog
  alias Trento.Operations.Commands.{CancelOperationSchedule, ScheduleOperation}
  alias Trento.Operations.Projections.OperationScheduleReadModel
  alias Trento.Operations.Schedules
  alias Trento.Repo
  alias Trento.Support.DateService

  @moduletag mocked_commanded: false

  setup do
    stub(DateService.Mock, :utc_now, fn -> ~U[2026-11-02 10:00:00.000000Z] end)
    :ok
  end

  defp attrs(target_ids) do
    %{
      target_type: "host",
      target_ids: target_ids,
      operation: "reboot",
      params: %{},
      starts_at: ~U[2026-11-07 02:00:00.000000Z],
      timezone: "Etc/UTC",
      recurrence: %{frequency: "monthly", interval: 1}
    }
  end

  test "should create one schedule per target with the same bulk id" do
    %{id: passing} = insert(:host, heartbeat: :passing, cluster_id: nil)
    %{id: critical} = insert(:host, heartbeat: :critical, cluster_id: nil)

    assert {:ok, bulk_id, results} =
             Schedules.create_bulk_schedules(
               attrs([passing, critical]),
               "admin",
               DateService.Mock
             )

    assert [
             {%OperationScheduleReadModel{
                target_id: ^passing,
                bulk_id: ^bulk_id,
                frequency: :monthly,
                created_by: "admin"
              }, []},
             {%OperationScheduleReadModel{target_id: ^critical, bulk_id: ^bulk_id},
              [%{message: "Trento agent is not currently running in the host"}]}
           ] = results

    entries = Repo.all(ActivityLog)
    assert 2 == length(entries)

    assert Enum.all?(
             entries,
             &match?(%{type: "operation_scheduled", metadata: %{"bulk_id" => ^bulk_id}}, &1)
           )
  end

  test "should schedule nothing when a target is unknown" do
    %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)

    assert {:error, :not_found} =
             Schedules.create_bulk_schedules(
               attrs([host_id, UUID.uuid4()]),
               "admin",
               DateService.Mock
             )

    assert [] == Repo.all(OperationScheduleReadModel)
    assert [] == Repo.all(ActivityLog)
  end

  test "should schedule nothing when the schedule is not valid" do
    %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)
    %{id: other_host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)

    assert {:error, %Ecto.Changeset{errors: [starts_at: _]}} =
             Schedules.create_bulk_schedules(
               Map.put(
                 attrs([host_id, other_host_id]),
                 :starts_at,
                 ~U[2026-11-01 02:00:00.000000Z]
               ),
               "admin",
               DateService.Mock
             )

    assert {:error, %Ecto.Changeset{}} =
             Schedules.create_bulk_schedules(
               Map.put(attrs([host_id, other_host_id]), :recurrence, %{
                 frequency: "monthly",
                 interval: 1,
                 ends_on: ~D[2026-11-07]
               }),
               "admin",
               DateService.Mock
             )

    assert [] == Repo.all(OperationScheduleReadModel)
    assert [] == Repo.all(ActivityLog)
  end

  @tag mocked_commanded: true
  test "should cancel the schedules already saved when one cannot be saved" do
    %{id: first} = insert(:host, heartbeat: :passing, cluster_id: nil)
    %{id: second} = insert(:host, heartbeat: :passing, cluster_id: nil)
    test_pid = self()

    expect(Trento.Commanded.Mock, :dispatch, fn %ScheduleOperation{
                                                  target_id: ^first,
                                                  schedule_id: schedule_id
                                                },
                                                _ ->
      send(test_pid, {:saved, schedule_id})
      :ok
    end)

    expect(Trento.Commanded.Mock, :dispatch, fn %ScheduleOperation{target_id: ^second}, _ ->
      {:error, :event_store_unavailable}
    end)

    expect(Trento.Commanded.Mock, :dispatch, fn %CancelOperationSchedule{schedule_id: schedule_id},
                                                _ ->
      send(test_pid, {:cancelled, schedule_id})
      :ok
    end)

    assert {:error, :event_store_unavailable} =
             Schedules.create_bulk_schedules(attrs([first, second]), "admin", DateService.Mock)

    assert_received {:saved, schedule_id}
    assert_received {:cancelled, ^schedule_id}
    assert [] == Repo.all(ActivityLog)
  end
end
