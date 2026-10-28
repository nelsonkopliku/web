# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.SchedulerTest do
  use ExUnit.Case
  use Trento.EventStoreCase
  use Trento.CommandedCase

  import Mox
  import Trento.Factory

  alias Commanded.Commands.ExecutionResult
  alias Trento.ActivityLog.ActivityLog
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.Infrastructure.Messaging.Adapter.Mock, as: Messaging
  alias Trento.Operations.Commands.{CompleteScheduledRun, TriggerScheduledRun}
  alias Trento.Operations.Events.ScheduledRunStarted
  alias Trento.Operations.Projections.OperationScheduleReadModel
  alias Trento.Operations.{ScheduledRun, Scheduler, Schedules}
  alias Trento.Operations.V1.OperationRequested
  alias Trento.Operations.ValueObjects.OperationParams
  alias Trento.Repo
  alias Trento.Support.DateService

  @moduletag mocked_commanded: false

  setup :verify_on_exit!

  @created_at ~U[2026-11-02 10:00:00.000000Z]
  @starts_at ~U[2026-11-07 02:00:00.000000Z]

  setup do
    %{id: host_id} = insert(:host, heartbeat: :passing, cluster_id: nil)
    %{host_id: host_id}
  end

  defp schedule!(host_id, recurrence \\ nil) do
    stub(DateService.Mock, :utc_now, fn -> @created_at end)

    {:ok, schedule, _} =
      Schedules.create_schedule(
        %{
          target_type: "host",
          target_id: host_id,
          operation: "reboot",
          starts_at: @starts_at,
          timezone: "Etc/UTC",
          recurrence: recurrence
        },
        "admin",
        DateService.Mock
      )

    schedule
  end

  defp run_at(now) do
    stub(DateService.Mock, :utc_now, fn -> now end)
    Scheduler.run_due(DateService.Mock)
  end

  defp entries(type), do: Enum.filter(Repo.all(ActivityLog), &(&1.type == type))

  test "should request a due one-time operation and remove the schedule", %{host_id: host_id} do
    %{id: schedule_id} = schedule!(host_id)
    test_pid = self()

    expect(Messaging, :publish, fn _, "requests", %OperationRequested{operation_id: id} ->
      send(test_pid, {:requested, id})
      :ok
    end)

    run_at(DateTime.add(@starts_at, 30, :second))

    assert [] == Repo.all(OperationScheduleReadModel)

    assert [
             %ActivityLog{
               actor: "system",
               metadata: %{
                 "schedule_id" => ^schedule_id,
                 "correlation_id" => ^schedule_id,
                 "operation_id" => operation_id,
                 "run_at" => "2026-11-07T02:00:00.000000Z"
               }
             }
           ] = entries("scheduled_operation_requested")

    assert_received {:requested, ^operation_id}
    assert operation_id == UUID.uuid5(schedule_id, DateTime.to_iso8601(@starts_at))

    assert %ScheduledRun{schedule_id: ^schedule_id, run_at: @starts_at} =
             Repo.get!(ScheduledRun, operation_id)
  end

  test "should move a periodic schedule to its next occurrence", %{host_id: host_id} do
    %{id: schedule_id} = schedule!(host_id, %{frequency: "daily", interval: 2})
    expect(Messaging, :publish, fn _, "requests", _ -> :ok end)

    run_at(DateTime.add(@starts_at, 30, :second))

    assert %OperationScheduleReadModel{
             next_run_at: ~U[2026-11-09 02:00:00.000000Z],
             occurrences: 1
           } = Repo.get!(OperationScheduleReadModel, schedule_id)
  end

  test "should end a periodic schedule after its last occurrence", %{host_id: host_id} do
    schedule!(host_id, %{frequency: "daily", interval: 1, max_occurrences: 1})
    expect(Messaging, :publish, fn _, "requests", _ -> :ok end)

    run_at(DateTime.add(@starts_at, 30, :second))

    assert [] == Repo.all(OperationScheduleReadModel)
  end

  test "should not request an operation whose policies fail", %{host_id: host_id} do
    schedule!(host_id, %{frequency: "daily", interval: 1})
    Repo.update_all(HostReadModel, set: [heartbeat: :critical])
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    run_at(DateTime.add(@starts_at, 30, :second))

    assert [
             %ActivityLog{
               severity: 13,
               metadata: %{
                 "reason" => "policies",
                 "errors" => [%{"message" => "Trento agent is not currently running in the host"}]
               }
             }
           ] = entries("scheduled_operation_request_failed")

    assert [%OperationScheduleReadModel{occurrences: 1}] = Repo.all(OperationScheduleReadModel)
  end

  test "should not request an operation on a target that is gone", %{host_id: host_id} do
    schedule!(host_id)
    Repo.delete_all(HostReadModel)
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    run_at(DateTime.add(@starts_at, 30, :second))

    assert [%ActivityLog{metadata: %{"reason" => "target_not_found"}}] =
             entries("scheduled_operation_request_failed")

    assert [] == Repo.all(OperationScheduleReadModel)
  end

  test "should not run an occurrence late when Trento was not available", %{host_id: host_id} do
    %{id: schedule_id} = schedule!(host_id, %{frequency: "daily", interval: 1})
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    # down for three days, back on 10 November at 01:00
    run_at(~U[2026-11-10 01:00:00.000000Z])

    assert [
             %ActivityLog{
               metadata: %{
                 "reason" => "not_available",
                 "run_at" => "2026-11-07T02:00:00.000000Z",
                 "host_id" => ^host_id
               }
             }
           ] = entries("scheduled_operation_request_failed")

    # 7 November is handled, 8 and 9 November are missed: they count
    assert %OperationScheduleReadModel{
             next_run_at: ~U[2026-11-10 02:00:00.000000Z],
             occurrences: 3
           } = Repo.get!(OperationScheduleReadModel, schedule_id)
  end

  test "should end a periodic schedule whose last occurrences were missed", %{
    host_id: host_id
  } do
    schedule!(host_id, %{frequency: "daily", interval: 1, max_occurrences: 2})
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    run_at(~U[2026-11-10 01:00:00.000000Z])

    assert [] == Repo.all(OperationScheduleReadModel)
  end

  @tag mocked_commanded: true
  test "should go on with the other schedules when one cannot run", %{host_id: host_id} do
    %{id: broken_id} =
      insert(:operation_schedule, target_id: host_id, next_run_at: @starts_at)

    %{id: schedule_id} =
      insert(:operation_schedule,
        target_id: host_id,
        next_run_at: DateTime.add(@starts_at, 1, :second)
      )

    operation_id = UUID.uuid4()

    expect(Trento.Commanded.Mock, :dispatch, fn %TriggerScheduledRun{schedule_id: ^broken_id},
                                                _ ->
      raise "the event store is gone"
    end)

    expect(Trento.Commanded.Mock, :dispatch, fn %TriggerScheduledRun{schedule_id: ^schedule_id},
                                                _ ->
      {:ok,
       %ExecutionResult{
         aggregate_uuid: schedule_id,
         aggregate_state: nil,
         aggregate_version: 2,
         metadata: %{},
         events: [
           %ScheduledRunStarted{
             schedule_id: schedule_id,
             run_at: DateTime.add(@starts_at, 1, :second),
             operation_id: operation_id,
             target_type: "host",
             target_id: host_id,
             operation: "reboot",
             params: %OperationParams{}
           }
         ]
       }}
    end)

    expect(Trento.Commanded.Mock, :dispatch, fn %CompleteScheduledRun{
                                                  schedule_id: ^schedule_id,
                                                  outcome: :requested
                                                },
                                                _ ->
      :ok
    end)

    expect(Messaging, :publish, fn _,
                                   "requests",
                                   %OperationRequested{operation_id: ^operation_id} ->
      :ok
    end)

    log =
      ExUnit.CaptureLog.capture_log(fn -> run_at(DateTime.add(@starts_at, 30, :second)) end)

    assert log =~ "Operation schedule #{broken_id} could not run"

    assert [%ActivityLog{metadata: %{"schedule_id" => ^schedule_id}}] =
             entries("scheduled_operation_requested")
  end

  test "should retry a request that cannot be sent until the grace period ends", %{
    host_id: host_id
  } do
    %{id: schedule_id} = schedule!(host_id)
    test_pid = self()

    expect(Messaging, :publish, 2, fn _, "requests", %OperationRequested{operation_id: id} ->
      send(test_pid, {:requested, id})
      {:error, :closed}
    end)

    run_at(DateTime.add(@starts_at, 60, :second))

    assert %OperationScheduleReadModel{next_run_at: @starts_at} =
             Repo.get!(OperationScheduleReadModel, schedule_id)

    assert [] == Enum.reject(Repo.all(ActivityLog), &(&1.type == "operation_scheduled"))

    # the next run, a minute later, sends the same request again
    run_at(DateTime.add(@starts_at, 120, :second))
    assert_received {:requested, operation_id}
    assert_received {:requested, ^operation_id}

    run_at(DateTime.add(@starts_at, 6, :minute))

    assert [] == Repo.all(OperationScheduleReadModel)

    assert [%ActivityLog{metadata: %{"reason" => "not_available"}}] =
             entries("scheduled_operation_request_failed")
  end

  @tag mocked_commanded: true
  test "should leave the run pending when its outcome cannot be recorded", %{host_id: host_id} do
    %{id: schedule_id} = insert(:operation_schedule, target_id: host_id, next_run_at: @starts_at)

    expect(Trento.Commanded.Mock, :dispatch, fn %TriggerScheduledRun{}, _ ->
      {:ok,
       %ExecutionResult{
         aggregate_uuid: schedule_id,
         aggregate_state: nil,
         aggregate_version: 2,
         metadata: %{},
         events: [
           %ScheduledRunStarted{
             schedule_id: schedule_id,
             run_at: @starts_at,
             operation_id: UUID.uuid4(),
             target_type: "host",
             target_id: host_id,
             operation: "reboot",
             params: %OperationParams{}
           }
         ]
       }}
    end)

    expect(Trento.Commanded.Mock, :dispatch, fn %CompleteScheduledRun{}, _ ->
      {:error, :event_store_unavailable}
    end)

    expect(Messaging, :publish, fn _, "requests", _ -> :ok end)

    log =
      ExUnit.CaptureLog.capture_log(fn -> run_at(DateTime.add(@starts_at, 30, :second)) end)

    assert log =~ "could not be recorded, the run starts again at the next run"
    assert [] == entries("scheduled_operation_requested")
  end

  @tag mocked_commanded: true
  test "should log a late occurrence whose trigger outlasts the read model", %{host_id: host_id} do
    %{id: schedule_id} = insert(:operation_schedule, target_id: host_id, next_run_at: @starts_at)
    expect(Trento.Commanded.Mock, :dispatch, fn _, _ -> {:error, :consistency_timeout} end)

    run_at(DateTime.add(@starts_at, 10, :minute))

    assert [%ActivityLog{metadata: %{"schedule_id" => ^schedule_id, "reason" => "not_available"}}] =
             entries("scheduled_operation_request_failed")
  end

  test "should leave the schedules that are not due", %{host_id: host_id} do
    %{id: schedule_id} = schedule!(host_id)
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    run_at(DateTime.add(@starts_at, -1, :second))

    assert %OperationScheduleReadModel{next_run_at: @starts_at, occurrences: 0} =
             Repo.get!(OperationScheduleReadModel, schedule_id)
  end
end
