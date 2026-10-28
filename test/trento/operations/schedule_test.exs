# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ScheduleTest do
  use Trento.AggregateCase, aggregate: Trento.Operations.Schedule, async: true

  alias Trento.Operations.Commands.ScheduleOperation
  alias Trento.Operations.Events.OperationScheduled
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
