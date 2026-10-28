# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.SchedulerTest do
  use ExUnit.Case, async: true
  use Trento.DataCase
  use Oban.Testing, repo: Trento.Repo

  import Ecto.Query, only: [from: 2]
  import Mox
  import Trento.Factory

  alias Trento.ActivityLog.ActivityLog
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.Infrastructure.Messaging.Adapter.Mock, as: Messaging
  alias Trento.Operations.{OperationSchedule, ScheduledRun, Scheduler, ScheduleJobs, Schedules}
  alias Trento.Support.DateService

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

  defp run_at(%OperationSchedule{id: id}, run_at, now) do
    stub(DateService.Mock, :utc_now, fn -> now end)
    Scheduler.run(id, run_at, DateService.Mock)
  end

  defp entries(type), do: Enum.filter(Repo.all(ActivityLog), &(&1.type == type))

  defp jobs, do: all_enqueued(worker: ScheduleJobs.worker())

  test "should request a due one-time operation and remove the schedule", %{host_id: host_id} do
    %{id: schedule_id} = schedule = schedule!(host_id)
    expect(Messaging, :publish, fn _, "requests", _ -> :ok end)

    assert :ok = run_at(schedule, @starts_at, DateTime.add(@starts_at, 30, :second))

    assert [] == Repo.all(OperationSchedule)

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

    assert %ScheduledRun{schedule_id: ^schedule_id} = Repo.get!(ScheduledRun, operation_id)
  end

  test "should move a periodic schedule to its next occurrence with a new job", %{
    host_id: host_id
  } do
    %{id: schedule_id} = schedule = schedule!(host_id, %{frequency: "daily", interval: 2})
    expect(Messaging, :publish, fn _, "requests", _ -> :ok end)

    run_at(schedule, @starts_at, DateTime.add(@starts_at, 30, :second))

    assert %OperationSchedule{next_run_at: ~U[2026-11-09 02:00:00.000000Z], occurrences: 1} =
             Repo.get!(OperationSchedule, schedule_id)

    assert ~U[2026-11-09 02:00:00.000000Z] in Enum.map(jobs(), & &1.scheduled_at)
  end

  test "should end a periodic schedule after its last occurrence", %{host_id: host_id} do
    schedule = schedule!(host_id, %{frequency: "daily", interval: 1, max_occurrences: 1})
    expect(Messaging, :publish, fn _, "requests", _ -> :ok end)

    run_at(schedule, @starts_at, DateTime.add(@starts_at, 30, :second))

    assert [] == Repo.all(OperationSchedule)
  end

  test "should not request an operation whose policies fail", %{host_id: host_id} do
    schedule = schedule!(host_id, %{frequency: "daily", interval: 1})
    Repo.update_all(HostReadModel, set: [heartbeat: :critical])
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    run_at(schedule, @starts_at, DateTime.add(@starts_at, 30, :second))

    assert [
             %ActivityLog{
               severity: 13,
               metadata: %{
                 "reason" => "policies",
                 "errors" => [%{"message" => "Trento agent is not currently running in the host"}]
               }
             }
           ] = entries("scheduled_operation_request_failed")

    assert [%OperationSchedule{occurrences: 1}] = Repo.all(OperationSchedule)
  end

  test "should not run an occurrence late, and count the missed ones", %{host_id: host_id} do
    %{id: schedule_id} = schedule = schedule!(host_id, %{frequency: "daily", interval: 1})
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    # down for three days, back on 10 November at 01:00
    run_at(schedule, @starts_at, ~U[2026-11-10 01:00:00.000000Z])

    assert [%ActivityLog{metadata: %{"reason" => "not_available"}}] =
             entries("scheduled_operation_request_failed")

    assert %OperationSchedule{next_run_at: ~U[2026-11-10 02:00:00.000000Z], occurrences: 3} =
             Repo.get!(OperationSchedule, schedule_id)
  end

  test "should end a periodic schedule whose last occurrences were missed", %{
    host_id: host_id
  } do
    schedule = schedule!(host_id, %{frequency: "daily", interval: 1, max_occurrences: 2})
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    run_at(schedule, @starts_at, ~U[2026-11-10 01:00:00.000000Z])

    assert [] == Repo.all(OperationSchedule)
  end

  test "should snooze a request that cannot be sent until the grace period ends", %{
    host_id: host_id
  } do
    %{id: schedule_id} = schedule = schedule!(host_id)
    expect(Messaging, :publish, fn _, "requests", _ -> {:error, :closed} end)

    assert {:snooze, 60} = run_at(schedule, @starts_at, DateTime.add(@starts_at, 60, :second))
    assert %OperationSchedule{next_run_at: @starts_at} = Repo.get!(OperationSchedule, schedule_id)

    assert :ok = run_at(schedule, @starts_at, DateTime.add(@starts_at, 6, :minute))

    assert [] == Repo.all(OperationSchedule)

    assert [%ActivityLog{metadata: %{"reason" => "not_available"}}] =
             entries("scheduled_operation_request_failed")
  end

  test "should do nothing for a job whose occurrence is not the next one", %{host_id: host_id} do
    %{id: schedule_id} = schedule = schedule!(host_id)
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    assert :ok =
             run_at(
               schedule,
               DateTime.add(@starts_at, -1, :day),
               DateTime.add(@starts_at, 30, :second)
             )

    assert :ok = Scheduler.run(UUID.uuid4(), @starts_at, DateService.Mock)

    assert %OperationSchedule{next_run_at: @starts_at, occurrences: 0} =
             Repo.get!(OperationSchedule, schedule_id)
  end

  test "should give a job back to a schedule that lost its own", %{host_id: host_id} do
    %{id: schedule_id} = schedule!(host_id)
    Repo.delete_all(from j in Oban.Job, where: j.worker == ^ScheduleJobs.worker())

    assert :ok = Scheduler.reconcile()

    assert [%Oban.Job{args: %{"schedule_id" => ^schedule_id}, scheduled_at: @starts_at}] = jobs()
    assert :ok = Scheduler.reconcile()
    assert [_] = jobs()
  end

  test "should run a job of the worker", %{host_id: host_id} do
    %{id: schedule_id} = schedule!(host_id)
    stub(DateService.Mock, :utc_now, fn -> DateTime.add(@starts_at, 30, :second) end)
    expect(Messaging, :publish, 0, fn _, _, _ -> :ok end)

    assert :ok =
             perform_job(Trento.Infrastructure.Jobs.ScheduledOperationJob, %{
               schedule_id: schedule_id,
               run_at: DateTime.add(@starts_at, -1, :day)
             })
  end
end
