# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.CreateTest do
  use ExUnit.Case
  use Trento.EventStoreCase
  use Trento.CommandedCase

  import Mox
  import Trento.Factory

  alias Trento.ActivityLog.ActivityLog
  alias Trento.MaintenanceWindows
  alias Trento.MaintenanceWindows.Projections.MaintenanceWindowReadModel, as: MaintenanceWindow
  alias Trento.Repo
  alias Trento.Support.DateService

  # The windows are aggregates, read back from their read model
  @moduletag mocked_commanded: false

  setup :verify_on_exit!

  @now ~U[2026-11-02 10:00:00.000000Z]

  setup do
    stub(DateService.Mock, :utc_now, fn -> @now end)
    :ok
  end

  defp attrs(target_type, target_id, overrides \\ %{}) do
    Map.merge(
      %{
        target_type: target_type,
        target_id: target_id,
        starts_at: ~U[2026-11-07 22:00:00.000000Z],
        timezone: "Europe/Berlin",
        duration_minutes: 240,
        recurrence: nil,
        forbids: ["checks_execution", "operations"]
      },
      overrides
    )
  end

  test "should set a one-time window on every target type" do
    for {target_type, %{id: target_id}} <- [
          {"host", insert(:host)},
          {"cluster", insert(:cluster)},
          {"database", insert(:database)},
          {"sap_system", insert(:sap_system)}
        ] do
      assert {:ok,
              %MaintenanceWindow{
                target_type: ^target_type,
                target_id: ^target_id,
                frequency: nil,
                forbid_checks_execution: true,
                forbid_operations: true,
                created_by: "admin"
              }} =
               MaintenanceWindows.create_window(
                 attrs(target_type, target_id),
                 "admin",
                 DateService.Mock
               )
    end
  end

  test "should set a periodic window that forbids one action" do
    %{id: host_id} = insert(:host)

    assert {:ok, %MaintenanceWindow{} = window} =
             MaintenanceWindows.create_window(
               attrs("host", host_id, %{
                 recurrence: %{frequency: "weekly", interval: 1, weekdays: [6], ends_on: nil},
                 forbids: ["operations"]
               }),
               "admin",
               DateService.Mock
             )

    assert ["operations"] == MaintenanceWindow.forbids(window)

    assert %{frequency: "weekly", interval: 1, weekdays: [6], ends_on: nil} ==
             MaintenanceWindow.recurrence(window)
  end

  test "should refuse an invalid window" do
    %{id: host_id} = insert(:host)

    for {overrides, field} <- [
          {%{starts_at: ~U[2026-11-01 22:00:00.000000Z]}, :starts_at},
          {%{duration_minutes: 0}, :duration_minutes},
          {%{duration_minutes: 44_641}, :duration_minutes},
          {%{forbids: []}, :forbids},
          {%{timezone: "Mars/Olympus_Mons"}, :timezone},
          {%{recurrence: %{frequency: "hourly", interval: 1}}, :recurrence},
          {%{recurrence: %{frequency: "daily", interval: 1, max_occurrences: 3}},
           :max_occurrences},
          {%{recurrence: %{frequency: "daily", interval: 1, ends_on: ~D[2026-11-07]}},
           :starts_at},
          {%{target_type: "application_instance"}, :target_type}
        ] do
      assert {:error, %Ecto.Changeset{} = changeset} =
               MaintenanceWindows.create_window(
                 attrs("host", host_id, overrides),
                 "admin",
                 DateService.Mock
               )

      assert Map.has_key?(Trento.DataCase.errors_on(changeset), field),
             "expected an error on #{field} for #{inspect(overrides)}"
    end

    assert [] == Repo.all(MaintenanceWindow)
  end

  test "should not set a window on an unknown or deregistered target" do
    %{id: deregistered_id} = insert(:host, deregistered_at: @now)

    for target_id <- [UUID.uuid4(), deregistered_id] do
      assert {:error, :not_found} ==
               MaintenanceWindows.create_window(
                 attrs("host", target_id),
                 "admin",
                 DateService.Mock
               )
    end

    assert [] == Repo.all(ActivityLog)
  end

  test "should log the window in the activity log and tell the UI" do
    TrentoWeb.Endpoint.subscribe("monitoring:maintenance_windows")
    %{id: cluster_id, name: name} = insert(:cluster)

    {:ok, %{id: window_id}} =
      MaintenanceWindows.create_window(attrs("cluster", cluster_id), "admin", DateService.Mock)

    assert [
             %ActivityLog{
               type: "maintenance_window_scheduled",
               actor: "admin",
               severity: 9,
               metadata: %{
                 "maintenance_window_id" => ^window_id,
                 "correlation_id" => ^window_id,
                 "cluster_id" => ^cluster_id,
                 "name" => ^name,
                 "forbids" => ["checks_execution", "operations"],
                 "duration_minutes" => 240
               }
             }
           ] = Repo.all(ActivityLog)

    assert_receive %Phoenix.Socket.Broadcast{
      event: "maintenance_windows_changed",
      payload: %{target_type: "cluster", target_id: ^cluster_id}
    }
  end

  @tag mocked_commanded: true
  test "should log a window saved while its read model is late" do
    %{id: host_id} = insert(:host)
    expect(Trento.Commanded.Mock, :dispatch, fn _, _ -> {:error, :consistency_timeout} end)

    assert {:error, :consistency_timeout} =
             MaintenanceWindows.create_window(attrs("host", host_id), "admin", DateService.Mock)

    assert [
             %ActivityLog{
               type: "maintenance_window_scheduled",
               actor: "admin",
               metadata: %{"host_id" => ^host_id, "duration_minutes" => 240}
             }
           ] = Repo.all(ActivityLog)
  end
end
