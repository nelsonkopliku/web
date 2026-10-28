# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksSchedulingDueTest do
  use ExUnit.Case, async: false
  use Trento.DataCase

  import Mox
  import Trento.Factory

  alias Trento.ChecksScheduling
  alias Trento.ChecksScheduling.ExecutionRequest
  alias Trento.ChecksScheduling.Projections.TargetChecksIntervalReadModel
  alias Trento.Infrastructure.Messaging.Adapter.Mock, as: Messaging
  alias Trento.Support.DateService

  setup :verify_on_exit!

  @now ~U[2026-11-02 10:00:00.000000Z]

  setup do
    previous = Application.get_env(:trento, :checks_execution)
    on_exit(fn -> Application.put_env(:trento, :checks_execution, previous) end)
    Application.put_env(:trento, :checks_execution, interval: nil)
    stub(DateService.Mock, :utc_now, fn -> @now end)
    :ok
  end

  defp host!(attrs \\ []),
    do: insert(:host, Keyword.merge([selected_checks: ["check_1"], heartbeat: :passing], attrs))

  defp settings!(target_id, attrs) do
    if interval = attrs[:interval] do
      Repo.insert!(%TargetChecksIntervalReadModel{
        target_id: target_id,
        target_type: "host",
        interval: interval
      })
    end

    if last_requested_at = attrs[:last_requested_at] do
      Repo.insert!(%ExecutionRequest{
        target_id: target_id,
        target_type: "host",
        last_requested_at: last_requested_at
      })
    end
  end

  defp requested_target_ids(fun) do
    test_pid = self()

    stub(Messaging, :publish, fn _, "executions", %{group_id: group_id} ->
      send(test_pid, {:requested, group_id})
      :ok
    end)

    fun.()
    collect([])
  end

  defp collect(acc) do
    receive do
      {:requested, id} -> collect([id | acc])
    after
      0 -> Enum.sort(acc)
    end
  end

  test "should request the targets whose interval elapsed and remember when" do
    %{id: never} = host!()
    %{id: elapsed} = host!()
    %{id: recent} = host!()
    settings!(elapsed, last_requested_at: ~U[2026-11-02 09:55:00.000000Z])
    settings!(recent, last_requested_at: ~U[2026-11-02 09:58:00.000000Z])

    assert Enum.sort([never, elapsed]) ==
             requested_target_ids(fn ->
               ChecksScheduling.request_due_executions(DateService.Mock)
             end)

    assert %ExecutionRequest{last_requested_at: @now} = Repo.get!(ExecutionRequest, never)
    assert %ExecutionRequest{last_requested_at: @now} = Repo.get!(ExecutionRequest, elapsed)
  end

  test "should follow the interval of each target" do
    %{id: overridden} = host!()
    settings!(overridden, interval: "6h", last_requested_at: ~U[2026-11-02 04:00:00.000000Z])
    %{id: not_yet} = host!()
    settings!(not_yet, interval: "6h", last_requested_at: ~U[2026-11-02 06:00:00.000000Z])

    assert [overridden] ==
             requested_target_ids(fn ->
               ChecksScheduling.request_due_executions(DateService.Mock)
             end)
  end

  test "should skip disabled, unchecked and deregistered targets" do
    %{id: disabled} = host!()
    settings!(disabled, interval: "disabled")

    host!(selected_checks: [])
    host!(deregistered_at: @now)

    assert [] ==
             requested_target_ids(fn ->
               ChecksScheduling.request_due_executions(DateService.Mock)
             end)
  end

  test "should request a target whose interval elapsed give or take half a minute" do
    %{id: almost} = host!()
    settings!(almost, last_requested_at: ~U[2026-11-02 09:55:20.000000Z])
    %{id: too_early} = host!()
    settings!(too_early, last_requested_at: ~U[2026-11-02 09:55:40.000000Z])

    assert [almost] ==
             requested_target_ids(fn ->
               ChecksScheduling.request_due_executions(DateService.Mock)
             end)
  end

  test "should skip the clusters whose checks cannot be executed" do
    insert(:cluster, type: :unknown, selected_checks: ["check_1"])

    assert [] ==
             requested_target_ids(fn ->
               ChecksScheduling.request_due_executions(DateService.Mock)
             end)
  end

  test "should request nothing when periodic executions are disabled globally" do
    {:ok, _} = Trento.Settings.update_checks_execution_settings(%{interval: "disabled"})
    host!()

    assert [] ==
             requested_target_ids(fn ->
               ChecksScheduling.request_due_executions(DateService.Mock)
             end)
  end
end
