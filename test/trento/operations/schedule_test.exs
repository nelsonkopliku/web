# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ScheduleTest do
  use Trento.AggregateCase, aggregate: Trento.Operations.Schedule, async: true

  alias Trento.Operations.Commands.{ChangeOperationSchedule, ScheduleOperation}
  alias Trento.Operations.Events.{OperationScheduleChanged, OperationScheduled}
  alias Trento.Operations.Schedule
  alias Trento.Operations.ValueObjects.{OperationParams, Recurrence}

  @requested_at ~U[2026-11-02 10:00:00.000000Z]
  # Saturday 7 November 2026
  @starts_at ~U[2026-11-07 02:00:00.000000Z]

  defp schedule_operation(schedule_id, overrides \\ %{}) do
    ScheduleOperation.new!(
      Map.merge(
        %{
          schedule_id: schedule_id,
          target_type: "host",
          target_id: "0a7a5d13-0e6e-4ac4-9f76-6b2d9d6a1b5e",
          operation: "reboot",
          params: %{},
          starts_at: @starts_at,
          timezone: "Etc/UTC",
          recurrence: nil,
          requested_at: @requested_at
        },
        overrides
      )
    )
  end

  describe "scheduling" do
    test "should schedule a one-time operation on its start" do
      schedule_id = UUID.uuid4()

      assert_events_and_state(
        [],
        schedule_operation(schedule_id),
        [
          %OperationScheduled{
            schedule_id: schedule_id,
            target_type: "host",
            target_id: "0a7a5d13-0e6e-4ac4-9f76-6b2d9d6a1b5e",
            operation: "reboot",
            params: %OperationParams{},
            starts_at: @starts_at,
            timezone: "Etc/UTC",
            recurrence: nil,
            next_run_at: @starts_at,
            bulk_id: nil
          }
        ],
        %Schedule{
          schedule_id: schedule_id,
          target_type: "host",
          target_id: "0a7a5d13-0e6e-4ac4-9f76-6b2d9d6a1b5e",
          operation: "reboot",
          params: %OperationParams{},
          starts_at: @starts_at,
          timezone: "Etc/UTC",
          recurrence: nil,
          next_run_at: @starts_at,
          occurrences: 0
        }
      )
    end

    test "should schedule a periodic operation on its first occurrence" do
      schedule_id = UUID.uuid4()

      command =
        schedule_operation(schedule_id, %{
          timezone: "Europe/Berlin",
          recurrence: %{frequency: :weekly, interval: 1, weekdays: [1], max_occurrences: 3}
        })

      assert_events(
        [],
        command,
        [
          %OperationScheduled{
            schedule_id: schedule_id,
            target_type: "host",
            target_id: "0a7a5d13-0e6e-4ac4-9f76-6b2d9d6a1b5e",
            operation: "reboot",
            params: %OperationParams{},
            starts_at: @starts_at,
            timezone: "Europe/Berlin",
            recurrence: %Recurrence{
              frequency: :weekly,
              interval: 1,
              weekdays: [1],
              max_occurrences: 3
            },
            # the first Monday, 03:00 in Berlin
            next_run_at: ~U[2026-11-09 02:00:00.000000Z]
          }
        ]
      )
    end

    test "should refuse a start before the request" do
      assert_error(
        schedule_operation(UUID.uuid4(), %{
          starts_at: ~U[2026-11-02 09:59:59.000000Z],
          recurrence: %{frequency: :daily, interval: 1}
        }),
        {:error, :operation_schedule_start_in_the_past}
      )
    end

    test "should refuse a recurrence that leaves no occurrence" do
      assert_error(
        schedule_operation(UUID.uuid4(), %{
          recurrence: %{frequency: :daily, interval: 1, ends_on: ~D[2026-11-07]}
        }),
        {:error, :operation_schedule_without_occurrences}
      )
    end

    test "should refuse to schedule an existing schedule again" do
      schedule_id = UUID.uuid4()

      assert_error(
        [
          %OperationScheduled{
            schedule_id: schedule_id,
            target_type: "host",
            target_id: UUID.uuid4(),
            operation: "reboot",
            params: %OperationParams{},
            starts_at: @starts_at,
            timezone: "Etc/UTC",
            next_run_at: @starts_at
          }
        ],
        schedule_operation(schedule_id),
        {:error, :operation_schedule_already_exists}
      )
    end
  end

  describe "changing" do
    defp scheduled(schedule_id, recurrence \\ nil) do
      %OperationScheduled{
        schedule_id: schedule_id,
        target_type: "host",
        target_id: "0a7a5d13-0e6e-4ac4-9f76-6b2d9d6a1b5e",
        operation: "reboot",
        params: %OperationParams{},
        starts_at: @starts_at,
        timezone: "Etc/UTC",
        recurrence: recurrence,
        next_run_at: @starts_at
      }
    end

    defp change(schedule_id, overrides) do
      ChangeOperationSchedule.new!(
        Map.merge(
          %{
            schedule_id: schedule_id,
            params: %{},
            starts_at: @starts_at,
            timezone: "Etc/UTC",
            recurrence: nil,
            requested_at: @requested_at
          },
          overrides
        )
      )
    end

    test "should replace the params and the timing of a schedule" do
      schedule_id = UUID.uuid4()

      assert_events_and_state(
        [scheduled(schedule_id, %Recurrence{frequency: :daily, interval: 1})],
        change(schedule_id, %{
          params: %{timeout: 300},
          starts_at: ~U[2026-11-10 04:00:00.000000Z],
          timezone: "Europe/Berlin"
        }),
        [
          %OperationScheduleChanged{
            schedule_id: schedule_id,
            params: %OperationParams{timeout: 300},
            starts_at: ~U[2026-11-10 04:00:00.000000Z],
            timezone: "Europe/Berlin",
            recurrence: nil,
            next_run_at: ~U[2026-11-10 04:00:00.000000Z]
          }
        ],
        fn %Schedule{} = schedule ->
          assert %Schedule{
                   params: %OperationParams{timeout: 300},
                   starts_at: ~U[2026-11-10 04:00:00.000000Z],
                   timezone: "Europe/Berlin",
                   recurrence: nil,
                   next_run_at: ~U[2026-11-10 04:00:00.000000Z],
                   occurrences: 0
                 } = schedule
        end
      )
    end

    test "should continue an ongoing periodic schedule with its next occurrence" do
      schedule_id = UUID.uuid4()
      recurrence = %{frequency: :daily, interval: 1, max_occurrences: 3}

      # The daily schedule started on 7 November; on 9 November at 10:00 its
      # params change, its start stays.
      assert_events(
        [scheduled(schedule_id, struct(Recurrence, recurrence))],
        change(schedule_id, %{
          recurrence: recurrence,
          params: %{timeout: 60},
          requested_at: ~U[2026-11-09 10:00:00.000000Z]
        }),
        [
          %OperationScheduleChanged{
            schedule_id: schedule_id,
            params: %OperationParams{timeout: 60},
            starts_at: @starts_at,
            timezone: "Etc/UTC",
            recurrence: struct(Recurrence, recurrence),
            next_run_at: ~U[2026-11-10 02:00:00.000000Z]
          }
        ]
      )
    end

    test "should refuse a new start in the past, or keeping the past start of a one-time schedule" do
      schedule_id = UUID.uuid4()

      assert_error(
        [scheduled(schedule_id)],
        change(schedule_id, %{starts_at: ~U[2026-11-01 04:00:00.000000Z]}),
        {:error, :operation_schedule_start_in_the_past}
      )

      assert_error(
        [scheduled(schedule_id)],
        change(schedule_id, %{requested_at: ~U[2026-11-09 10:00:00.000000Z]}),
        {:error, :operation_schedule_start_in_the_past}
      )
    end

    test "should refuse a recurrence that leaves no occurrence" do
      schedule_id = UUID.uuid4()

      assert_error(
        [scheduled(schedule_id)],
        change(schedule_id, %{
          recurrence: %{frequency: :weekly, interval: 1, ends_on: ~D[2026-11-07]}
        }),
        {:error, :operation_schedule_without_occurrences}
      )
    end

    test "should not change a schedule that does not exist" do
      assert_error(
        change(UUID.uuid4(), %{}),
        {:error, :operation_schedule_not_found}
      )
    end
  end

  describe "commands" do
    test "should refuse an operation that cannot be scheduled on the target" do
      for {overrides, field} <- [
            {%{operation: "saptune_solution_apply"}, :operation},
            {%{target_type: "cluster"}, :operation},
            {%{target_type: "rack"}, :target_type},
            {%{timezone: "Mars/Olympus_Mons"}, :timezone},
            {%{recurrence: %{frequency: :hourly, interval: 1}}, :recurrence},
            {%{recurrence: %{frequency: :daily, interval: 0}}, :recurrence},
            {%{recurrence: %{frequency: :weekly, interval: 1, weekdays: [0, 8]}}, :recurrence},
            {%{params: %{timeout: "soon"}}, :params}
          ] do
        attrs =
          Map.merge(
            %{
              schedule_id: UUID.uuid4(),
              target_type: "host",
              target_id: UUID.uuid4(),
              operation: "reboot",
              params: %{},
              starts_at: @starts_at,
              timezone: "Etc/UTC",
              requested_at: @requested_at
            },
            overrides
          )

        assert {:error, {:validation, errors}} = ScheduleOperation.new(attrs)

        assert Map.has_key?(errors, field),
               "expected an error on #{field} for #{inspect(overrides)}, got #{inspect(errors)}"
      end
    end
  end
end
