# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ScheduleRunsTest do
  use Trento.AggregateCase, aggregate: Trento.Operations.Schedule, async: true

  alias Trento.Operations.Commands.{
    CancelOperationSchedule,
    ChangeOperationSchedule,
    CompleteScheduledRun,
    TriggerScheduledRun
  }

  alias Trento.Operations.Events.{
    OperationScheduleCancelled,
    OperationScheduleChanged,
    OperationScheduled,
    ScheduledOperationRequested,
    ScheduledOperationRequestFailed,
    ScheduledRunStarted
  }

  alias Trento.Operations.Schedule

  alias Trento.Operations.ValueObjects.{
    OperationParams,
    PendingRun,
    PolicyError,
    PolicyErrorResource,
    Recurrence
  }

  @target_id "0a7a5d13-0e6e-4ac4-9f76-6b2d9d6a1b5e"
  # Saturday 7 November 2026
  @run_at ~U[2026-11-07 02:00:00.000000Z]

  defp scheduled(schedule_id, recurrence \\ nil) do
    %OperationScheduled{
      schedule_id: schedule_id,
      target_type: "host",
      target_id: @target_id,
      operation: "reboot",
      params: %OperationParams{},
      starts_at: @run_at,
      timezone: "Etc/UTC",
      recurrence: recurrence,
      next_run_at: @run_at
    }
  end

  defp operation_id(schedule_id), do: UUID.uuid5(schedule_id, DateTime.to_iso8601(@run_at))

  defp started(schedule_id, started_at \\ DateTime.add(@run_at, 20, :second)) do
    %ScheduledRunStarted{
      schedule_id: schedule_id,
      run_at: @run_at,
      operation_id: operation_id(schedule_id),
      target_type: "host",
      target_id: @target_id,
      operation: "reboot",
      params: %OperationParams{},
      started_at: started_at
    }
  end

  defp trigger(schedule_id, triggered_at, run_at \\ @run_at),
    do:
      TriggerScheduledRun.new!(%{
        schedule_id: schedule_id,
        run_at: run_at,
        triggered_at: triggered_at
      })

  defp complete(schedule_id, attrs),
    do:
      CompleteScheduledRun.new!(
        Map.merge(
          %{
            schedule_id: schedule_id,
            run_at: @run_at,
            outcome: :requested,
            completed_at: DateTime.add(@run_at, 21, :second)
          },
          attrs
        )
      )

  describe "triggering" do
    test "should start the run of a due occurrence with an operation id of its own" do
      schedule_id = UUID.uuid4()

      assert_events_and_state(
        [scheduled(schedule_id)],
        trigger(schedule_id, DateTime.add(@run_at, 20, :second)),
        [started(schedule_id)],
        fn %Schedule{} = schedule ->
          assert %Schedule{
                   next_run_at: @run_at,
                   pending_run: %PendingRun{
                     run_at: @run_at,
                     operation_id: operation_id,
                     started_at: ~U[2026-11-07 02:00:20.000000Z]
                   }
                 } = schedule

          assert operation_id == operation_id(schedule_id)
        end
      )
    end

    test "should not start a run that is not the next occurrence" do
      schedule_id = UUID.uuid4()

      assert_error(
        [scheduled(schedule_id)],
        trigger(schedule_id, @run_at, ~U[2026-11-06 02:00:00.000000Z]),
        {:error, :operation_schedule_stale_run}
      )
    end

    test "should not start again a run that started a moment ago" do
      schedule_id = UUID.uuid4()

      assert_error(
        [scheduled(schedule_id), started(schedule_id)],
        trigger(schedule_id, DateTime.add(@run_at, 30, :second)),
        {:error, :operation_schedule_run_pending}
      )
    end

    test "should start again a run whose outcome is not recorded, with the same operation id" do
      schedule_id = UUID.uuid4()

      assert_events(
        [scheduled(schedule_id), started(schedule_id)],
        trigger(schedule_id, DateTime.add(@run_at, 80, :second)),
        [started(schedule_id, DateTime.add(@run_at, 80, :second))]
      )
    end

    test "should fail an occurrence when Trento was not available, counting the missed ones" do
      schedule_id = UUID.uuid4()

      # down for three days, back on 10 November at 01:00: 7 November is
      # handled, 8 and 9 November are missed
      assert_events_and_state(
        [scheduled(schedule_id, %Recurrence{frequency: :daily, interval: 1})],
        trigger(schedule_id, ~U[2026-11-10 01:00:00.000000Z]),
        [
          %ScheduledOperationRequestFailed{
            schedule_id: schedule_id,
            run_at: @run_at,
            reason: :not_available,
            errors: [],
            occurrences: 3,
            next_run_at: ~U[2026-11-10 02:00:00.000000Z]
          }
        ],
        fn %Schedule{} = schedule ->
          assert %Schedule{
                   next_run_at: ~U[2026-11-10 02:00:00.000000Z],
                   occurrences: 3,
                   pending_run: nil
                 } = schedule
        end
      )
    end

    test "should give up a run whose outcome is not recorded after the grace period" do
      schedule_id = UUID.uuid4()

      assert_events_and_state(
        [scheduled(schedule_id), started(schedule_id)],
        trigger(schedule_id, DateTime.add(@run_at, 301, :second)),
        [
          %ScheduledOperationRequestFailed{
            schedule_id: schedule_id,
            run_at: @run_at,
            reason: :not_available,
            errors: [],
            occurrences: 1,
            next_run_at: nil
          }
        ],
        fn %Schedule{} = schedule ->
          assert %Schedule{next_run_at: nil, pending_run: nil} = schedule
        end
      )
    end

    test "should end a periodic schedule whose last occurrences were missed" do
      schedule_id = UUID.uuid4()

      assert_events(
        [scheduled(schedule_id, %Recurrence{frequency: :daily, interval: 1, max_occurrences: 2})],
        trigger(schedule_id, ~U[2026-11-10 01:00:00.000000Z]),
        [
          %ScheduledOperationRequestFailed{
            schedule_id: schedule_id,
            run_at: @run_at,
            reason: :not_available,
            errors: [],
            occurrences: 2,
            next_run_at: nil
          }
        ]
      )
    end
  end

  describe "completing" do
    test "should record a requested occurrence and move to the next one" do
      schedule_id = UUID.uuid4()

      assert_events_and_state(
        [
          scheduled(schedule_id, %Recurrence{frequency: :daily, interval: 2}),
          started(schedule_id)
        ],
        complete(schedule_id, %{outcome: :requested}),
        [
          %ScheduledOperationRequested{
            schedule_id: schedule_id,
            run_at: @run_at,
            operation_id: operation_id(schedule_id),
            target_type: "host",
            target_id: @target_id,
            operation: "reboot",
            params: %OperationParams{},
            occurrences: 1,
            next_run_at: ~U[2026-11-09 02:00:00.000000Z]
          }
        ],
        fn %Schedule{} = schedule ->
          assert %Schedule{
                   next_run_at: ~U[2026-11-09 02:00:00.000000Z],
                   occurrences: 1,
                   pending_run: nil
                 } = schedule
        end
      )
    end

    test "should end a one-time schedule after its run, whatever the outcome" do
      schedule_id = UUID.uuid4()
      initial = [scheduled(schedule_id), started(schedule_id)]

      errors = [
        %{
          message: "Trento agent is not currently running in the host",
          metadata: [%{id: @target_id, label: "vmhana01", type: :host}]
        }
      ]

      assert_events(
        initial,
        complete(schedule_id, %{outcome: :failed, reason: :policies, errors: errors}),
        [
          %ScheduledOperationRequestFailed{
            schedule_id: schedule_id,
            run_at: @run_at,
            reason: :policies,
            errors: [
              %PolicyError{
                message: "Trento agent is not currently running in the host",
                metadata: [%PolicyErrorResource{id: @target_id, label: "vmhana01", type: :host}]
              }
            ],
            occurrences: 1,
            next_run_at: nil
          }
        ]
      )

      ended = [
        %ScheduledOperationRequested{
          schedule_id: schedule_id,
          run_at: @run_at,
          operation_id: operation_id(schedule_id),
          occurrences: 1,
          next_run_at: nil
        }
      ]

      assert_error(
        initial ++ ended,
        trigger(schedule_id, DateTime.add(@run_at, 40, :second)),
        {:error, :operation_schedule_not_found}
      )
    end

    test "should end a periodic schedule after its last occurrence" do
      schedule_id = UUID.uuid4()

      assert_state(
        [
          scheduled(schedule_id, %Recurrence{frequency: :daily, interval: 1, max_occurrences: 1}),
          started(schedule_id)
        ],
        complete(schedule_id, %{}),
        fn %Schedule{} = schedule -> assert %Schedule{next_run_at: nil} = schedule end
      )
    end

    test "should refuse the outcome of a run that did not start" do
      schedule_id = UUID.uuid4()

      assert_error(
        [scheduled(schedule_id)],
        complete(schedule_id, %{}),
        {:error, :operation_schedule_stale_run}
      )

      assert_error(
        [scheduled(schedule_id), started(schedule_id)],
        complete(schedule_id, %{run_at: ~U[2026-11-06 02:00:00.000000Z]}),
        {:error, :operation_schedule_stale_run}
      )
    end

    test "should record the outcome of a run that started before a change, without moving on" do
      schedule_id = UUID.uuid4()

      changed = %OperationScheduleChanged{
        schedule_id: schedule_id,
        params: %OperationParams{timeout: 60},
        starts_at: ~U[2026-11-10 02:00:00.000000Z],
        timezone: "Etc/UTC",
        recurrence: nil,
        next_run_at: ~U[2026-11-10 02:00:00.000000Z]
      }

      assert_events_and_state(
        [scheduled(schedule_id), started(schedule_id), changed],
        complete(schedule_id, %{}),
        [
          %ScheduledOperationRequested{
            schedule_id: schedule_id,
            run_at: @run_at,
            operation_id: operation_id(schedule_id),
            target_type: "host",
            target_id: @target_id,
            operation: "reboot",
            params: %OperationParams{},
            occurrences: 0,
            next_run_at: ~U[2026-11-10 02:00:00.000000Z]
          }
        ],
        fn %Schedule{} = schedule ->
          assert %Schedule{
                   next_run_at: ~U[2026-11-10 02:00:00.000000Z],
                   params: %OperationParams{timeout: 60},
                   pending_run: nil
                 } = schedule
        end
      )
    end

    test "should record the outcome of a run that started before a cancellation" do
      schedule_id = UUID.uuid4()

      initial = [
        scheduled(schedule_id, %Recurrence{frequency: :daily, interval: 1}),
        started(schedule_id),
        %OperationScheduleCancelled{schedule_id: schedule_id}
      ]

      assert_events(
        initial,
        complete(schedule_id, %{}),
        [
          %ScheduledOperationRequested{
            schedule_id: schedule_id,
            run_at: @run_at,
            operation_id: operation_id(schedule_id),
            target_type: "host",
            target_id: @target_id,
            operation: "reboot",
            params: %OperationParams{},
            occurrences: 0,
            next_run_at: nil
          }
        ]
      )

      assert_error(
        initial,
        trigger(schedule_id, DateTime.add(@run_at, 80, :second)),
        {:error, :operation_schedule_not_found}
      )

      assert_error(
        initial,
        CancelOperationSchedule.new!(%{schedule_id: schedule_id}),
        {:error, :operation_schedule_not_found}
      )
    end

    test "should keep the start of an ongoing run when the schedule changes" do
      schedule_id = UUID.uuid4()

      assert_state(
        [
          scheduled(schedule_id, %Recurrence{frequency: :daily, interval: 1}),
          started(schedule_id)
        ],
        ChangeOperationSchedule.new!(%{
          schedule_id: schedule_id,
          params: %{timeout: 60},
          starts_at: @run_at,
          timezone: "Etc/UTC",
          recurrence: %{frequency: :daily, interval: 1},
          requested_at: DateTime.add(@run_at, 30, :second)
        }),
        fn %Schedule{} = schedule ->
          assert %Schedule{
                   next_run_at: ~U[2026-11-08 02:00:00.000000Z],
                   occurrences: 0,
                   pending_run: %PendingRun{run_at: @run_at}
                 } = schedule
        end
      )
    end
  end
end
