# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.ChangeTest do
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

  @created_at ~U[2026-11-02 10:00:00.000000Z]
  @starts_at ~U[2026-11-04 02:00:00.000000Z]

  setup do
    stub(DateService.Mock, :utc_now, fn -> @created_at end)
    %{id: host_id} = insert(:host)

    {:ok, window} =
      MaintenanceWindows.create_window(
        %{
          target_type: "host",
          target_id: host_id,
          starts_at: @starts_at,
          timezone: "Etc/UTC",
          duration_minutes: 120,
          forbids: ["operations"]
        },
        "admin",
        DateService.Mock
      )

    %{window: window}
  end

  defp change(window_id, attrs, now) do
    stub(DateService.Mock, :utc_now, fn -> now end)

    MaintenanceWindows.update_window(
      window_id,
      Map.merge(
        %{
          starts_at: @starts_at,
          timezone: "Etc/UTC",
          duration_minutes: 120,
          forbids: ["operations"]
        },
        attrs
      ),
      "operator",
      DateService.Mock
    )
  end

  test "should replace the timing and the forbidden actions", %{window: %{id: window_id}} do
    assert {:ok,
            %MaintenanceWindow{
              id: ^window_id,
              starts_at: ~U[2026-11-05 03:00:00.000000Z],
              frequency: "weekly",
              forbid_checks_execution: true,
              forbid_operations: false,
              created_by: "admin"
            }} =
             change(
               window_id,
               %{
                 starts_at: ~U[2026-11-05 03:00:00.000000Z],
                 recurrence: %{frequency: "weekly", interval: 1, weekdays: [4]},
                 forbids: ["checks_execution"]
               },
               @created_at
             )

    assert %ActivityLog{actor: "operator", metadata: %{"correlation_id" => ^window_id}} =
             Repo.get_by!(ActivityLog, type: "maintenance_window_changed")
  end

  test "should change an ongoing window and keep its start", %{window: %{id: window_id}} do
    during = ~U[2026-11-04 03:00:00.000000Z]

    assert {:ok, %MaintenanceWindow{duration_minutes: 90, forbid_checks_execution: true}} =
             change(
               window_id,
               %{duration_minutes: 90, forbids: ["operations", "checks_execution"]},
               during
             )

    # Ending it before now leaves nothing to change: the window is deleted instead
    assert {:error, %Ecto.Changeset{errors: [starts_at: _]}} =
             change(window_id, %{duration_minutes: 30}, during)

    assert {:error, %Ecto.Changeset{errors: [starts_at: {"is in the past", _}]}} =
             change(window_id, %{starts_at: ~U[2026-11-04 02:30:00.000000Z]}, during)
  end

  test "should refuse an invalid change", %{window: %{id: window_id}} do
    assert {:error, %Ecto.Changeset{errors: [forbids: _]}} =
             change(window_id, %{forbids: []}, @created_at)

    assert {:ok, %MaintenanceWindow{forbid_operations: true}} =
             MaintenanceWindows.get_window(window_id)
  end

  test "should not find an unknown window" do
    assert {:error, :not_found} == change(UUID.uuid4(), %{}, @created_at)
  end

  test "should not find a window that the read model still shows but is deleted", %{
    window: %{id: window_id}
  } do
    Application.put_env(:trento, Trento.Commanded, adapter: Trento.Commanded.Mock)

    expect(Trento.Commanded.Mock, :dispatch, fn _, _ ->
      {:error, :maintenance_window_not_found}
    end)

    assert {:error, :not_found} == change(window_id, %{}, @created_at)
  end
end
