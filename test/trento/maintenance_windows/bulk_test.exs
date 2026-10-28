# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.BulkTest do
  use ExUnit.Case, async: true
  use Trento.DataCase

  import Mox
  import Trento.Factory

  alias Trento.ActivityLog.ActivityLog
  alias Trento.MaintenanceWindows
  alias Trento.MaintenanceWindows.MaintenanceWindow
  alias Trento.Support.DateService

  setup do
    stub(DateService.Mock, :utc_now, fn -> ~U[2026-11-02 10:00:00.000000Z] end)
    :ok
  end

  defp attrs(target_ids, overrides \\ %{}) do
    Map.merge(
      %{
        target_type: "host",
        target_ids: target_ids,
        starts_at: ~U[2026-11-07 22:00:00.000000Z],
        timezone: "Etc/UTC",
        duration_minutes: 60,
        recurrence: nil,
        forbids: ["operations"]
      },
      overrides
    )
  end

  test "should set one window per target with the same bulk id" do
    [%{id: first}, %{id: second}] = insert_list(2, :host)

    assert {:ok, bulk_id,
            [
              %MaintenanceWindow{target_id: ^first, bulk_id: bulk_id},
              %MaintenanceWindow{target_id: ^second, bulk_id: bulk_id}
            ]} =
             MaintenanceWindows.create_bulk_windows(
               attrs([first, second]),
               "admin",
               DateService.Mock
             )

    entries = Repo.all(ActivityLog)
    assert 2 == length(entries)

    assert Enum.all?(
             entries,
             &match?(
               %{type: "maintenance_window_scheduled", metadata: %{"bulk_id" => ^bulk_id}},
               &1
             )
           )
  end

  test "should set nothing when a target is unknown or the window is not valid" do
    %{id: host_id} = insert(:host)

    assert {:error, :not_found} ==
             MaintenanceWindows.create_bulk_windows(
               attrs([host_id, UUID.uuid4()]),
               "admin",
               DateService.Mock
             )

    assert {:error, %Ecto.Changeset{}} =
             MaintenanceWindows.create_bulk_windows(
               attrs([host_id], %{forbids: []}),
               "admin",
               DateService.Mock
             )

    assert [] == Repo.all(MaintenanceWindow)
    assert [] == Repo.all(ActivityLog)
  end
end
