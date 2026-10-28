# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.MaintenanceWindowTest do
  use Trento.AggregateCase, aggregate: Trento.MaintenanceWindows.MaintenanceWindow, async: true

  alias Trento.MaintenanceWindows.Commands.{ChangeMaintenanceWindow, ScheduleMaintenanceWindow}
  alias Trento.MaintenanceWindows.Events.{MaintenanceWindowChanged, MaintenanceWindowScheduled}
  alias Trento.MaintenanceWindows.MaintenanceWindow
  alias Trento.MaintenanceWindows.ValueObjects.Recurrence

  @requested_at ~U[2026-11-02 10:00:00.000000Z]
  @starts_at ~U[2026-11-07 22:00:00.000000Z]
  @target_id "0a7a5d13-0e6e-4ac4-9f76-6b2d9d6a1b5e"

  defp schedule(window_id, overrides \\ %{}) do
    ScheduleMaintenanceWindow.new!(
      Map.merge(
        %{
          window_id: window_id,
          target_type: "cluster",
          target_id: @target_id,
          starts_at: @starts_at,
          timezone: "Europe/Berlin",
          duration_minutes: 240,
          recurrence: nil,
          forbids: ["checks_execution", "operations"],
          requested_at: @requested_at
        },
        overrides
      )
    )
  end

  defp scheduled(window_id) do
    %MaintenanceWindowScheduled{
      window_id: window_id,
      target_type: "cluster",
      target_id: @target_id,
      starts_at: @starts_at,
      timezone: "Europe/Berlin",
      duration_minutes: 240,
      recurrence: nil,
      forbids: [:checks_execution, :operations]
    }
  end

  describe "scheduling" do
    test "should set a window on a target" do
      window_id = UUID.uuid4()

      assert_events_and_state(
        [],
        schedule(window_id),
        [scheduled(window_id)],
        fn window ->
          assert %MaintenanceWindow{
                   window_id: ^window_id,
                   target_type: "cluster",
                   forbids: [:checks_execution, :operations]
                 } = window
        end
      )
    end

    test "should set a periodic window that forbids one action" do
      window_id = UUID.uuid4()

      assert_events(
        [],
        schedule(window_id, %{
          recurrence: %{frequency: :weekly, interval: 1, weekdays: [6]},
          forbids: ["operations"]
        }),
        [
          %MaintenanceWindowScheduled{
            scheduled(window_id)
            | recurrence: %Recurrence{frequency: :weekly, interval: 1, weekdays: [6]},
              forbids: [:operations]
          }
        ]
      )
    end

    test "should refuse a window that starts before the request or has no occurrence" do
      assert_error(
        schedule(UUID.uuid4(), %{starts_at: ~U[2026-11-02 09:00:00.000000Z]}),
        {:error, :maintenance_window_start_in_the_past}
      )

      assert_error(
        schedule(UUID.uuid4(), %{
          recurrence: %{frequency: :daily, interval: 1, ends_on: ~D[2026-11-07]}
        }),
        {:error, :maintenance_window_over}
      )
    end

    test "should refuse to set an existing window again" do
      window_id = UUID.uuid4()

      assert_error(
        [scheduled(window_id)],
        schedule(window_id),
        {:error, :maintenance_window_already_exists}
      )
    end
  end

  describe "changing" do
    defp change(window_id, overrides) do
      ChangeMaintenanceWindow.new!(
        Map.merge(
          %{
            window_id: window_id,
            starts_at: @starts_at,
            timezone: "Europe/Berlin",
            duration_minutes: 240,
            recurrence: nil,
            forbids: ["operations"],
            requested_at: @requested_at
          },
          overrides
        )
      )
    end

    test "should replace the timing and the forbidden actions" do
      window_id = UUID.uuid4()

      assert_events_and_state(
        [scheduled(window_id)],
        change(window_id, %{duration_minutes: 30, forbids: ["checks_execution"]}),
        [
          %MaintenanceWindowChanged{
            window_id: window_id,
            starts_at: @starts_at,
            timezone: "Europe/Berlin",
            duration_minutes: 30,
            recurrence: nil,
            forbids: [:checks_execution]
          }
        ],
        fn window ->
          assert %MaintenanceWindow{duration_minutes: 30, forbids: [:checks_execution]} = window
        end
      )
    end

    test "should change an ongoing window and keep its start" do
      window_id = UUID.uuid4()
      during = ~U[2026-11-07 23:00:00.000000Z]

      assert_events(
        [scheduled(window_id)],
        change(window_id, %{duration_minutes: 90, requested_at: during}),
        [
          %MaintenanceWindowChanged{
            window_id: window_id,
            starts_at: @starts_at,
            timezone: "Europe/Berlin",
            duration_minutes: 90,
            recurrence: nil,
            forbids: [:operations]
          }
        ]
      )

      assert_error(
        [scheduled(window_id)],
        change(window_id, %{duration_minutes: 30, requested_at: during}),
        {:error, :maintenance_window_over}
      )

      assert_error(
        [scheduled(window_id)],
        change(window_id, %{starts_at: ~U[2026-11-07 22:30:00.000000Z], requested_at: during}),
        {:error, :maintenance_window_start_in_the_past}
      )
    end

    test "should not change a window that does not exist" do
      assert_error(change(UUID.uuid4(), %{}), {:error, :maintenance_window_not_found})
    end
  end

  describe "commands" do
    test "should refuse an invalid window" do
      for {overrides, field} <- [
            {%{duration_minutes: 0}, :duration_minutes},
            {%{duration_minutes: 44_641}, :duration_minutes},
            {%{forbids: []}, :forbids},
            {%{forbids: ["reboots"]}, :forbids},
            {%{timezone: "Mars/Olympus_Mons"}, :timezone},
            {%{recurrence: %{frequency: :hourly, interval: 1}}, :recurrence},
            {%{recurrence: %{frequency: :daily, interval: 1, max_occurrences: 3}},
             :max_occurrences},
            {%{target_type: "application_instance"}, :target_type}
          ] do
        attrs =
          Map.merge(
            %{
              window_id: UUID.uuid4(),
              target_type: "host",
              target_id: UUID.uuid4(),
              starts_at: @starts_at,
              timezone: "Etc/UTC",
              duration_minutes: 60,
              forbids: ["operations"],
              requested_at: @requested_at
            },
            overrides
          )

        assert {:error, {:validation, errors}} = ScheduleMaintenanceWindow.new(attrs)

        assert Map.has_key?(errors, field),
               "expected an error on #{field} for #{inspect(overrides)}, got #{inspect(errors)}"
      end
    end
  end
end
