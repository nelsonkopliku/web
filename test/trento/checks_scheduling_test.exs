# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksSchedulingTest do
  use ExUnit.Case, async: false
  use Trento.DataCase

  import Mox
  import Trento.Factory
  import Trento.Support.Helpers.ChecksIntervalTestHelper

  alias Trento.ChecksScheduling
  alias Trento.ChecksScheduling.ExecutionRequest
  alias Trento.Clusters.Commands.ChangeClusterChecksInterval
  alias Trento.Hosts.Commands.ChangeHostChecksInterval
  alias Trento.Settings
  alias Trento.Support.DateService

  setup :verify_on_exit!

  # Monday 2 November 2026, 10:00 UTC
  @now ~U[2026-11-02 10:00:00.000000Z]

  setup do
    previous = Application.get_env(:trento, :checks_execution)
    on_exit(fn -> Application.put_env(:trento, :checks_execution, previous) end)
    Application.put_env(:trento, :checks_execution, interval: nil)

    stub(DateService.Mock, :utc_now, fn -> @now end)
    stub_checks_interval_commands()
    %{id: host_id} = insert(:host)
    %{host_id: host_id}
  end

  defp get_schedule(host_id),
    do: ChecksScheduling.get_target_schedule(:host, host_id, DateService.Mock)

  defp put_schedule(host_id, attrs),
    do: ChecksScheduling.update_target_schedule(:host, host_id, attrs, DateService.Mock)

  defp requested_at(target_id, at) do
    Repo.insert!(
      %ExecutionRequest{target_id: target_id, target_type: "host", last_requested_at: at},
      on_conflict: [set: [last_requested_at: at]],
      conflict_target: :target_id
    )
  end

  test "should use the global interval when the target has none", %{host_id: host_id} do
    assert {:ok,
            %{
              interval: nil,
              effective_interval: "5m",
              global_interval: "5m",
              last_requested_at: nil,
              next_execution_at: @now
            }} == get_schedule(host_id)
  end

  test "should override the global interval for the target", %{host_id: host_id} do
    {:ok, _} = Settings.update_checks_execution_settings(%{interval: "15m"})
    requested_at(host_id, ~U[2026-11-02 09:00:00.000000Z])

    assert {:ok, %{interval: "6h", effective_interval: "6h", global_interval: "15m"}} =
             put_schedule(host_id, %{interval: "6h"})

    assert {:ok,
            %{
              interval: "6h",
              last_requested_at: ~U[2026-11-02 09:00:00.000000Z],
              next_execution_at: ~U[2026-11-02 15:00:00.000000Z]
            }} = get_schedule(host_id)

    assert {:ok, %{interval: nil, effective_interval: "15m"}} =
             put_schedule(host_id, %{interval: nil})

    assert {:ok, %{interval: nil}} = get_schedule(host_id)
  end

  test "should plan no execution when periodic executions are disabled", %{host_id: host_id} do
    assert {:ok, %{effective_interval: "disabled", next_execution_at: nil}} =
             put_schedule(host_id, %{interval: "disabled"})

    {:ok, _} = Settings.update_checks_execution_settings(%{interval: "disabled"})
    {:ok, _} = put_schedule(host_id, %{interval: nil})

    assert {:ok, %{effective_interval: "disabled", next_execution_at: nil}} =
             get_schedule(host_id)
  end

  test "should refuse an interval that is not allowed", %{host_id: host_id} do
    assert {:error, %Ecto.Changeset{}} = put_schedule(host_id, %{interval: "7m"})
  end

  test "should not find an unknown or deregistered target" do
    %{id: deregistered_id} = insert(:host, deregistered_at: @now)

    for host_id <- [UUID.uuid4(), deregistered_id] do
      assert {:error, :not_found} == get_schedule(host_id)
      assert {:error, :not_found} == put_schedule(host_id, %{interval: "1h"})
    end
  end

  test "should not find a target that the aggregate does not know" do
    %{id: host_id} = insert(:host)

    expect(Trento.Commanded.Mock, :dispatch, fn %ChangeHostChecksInterval{host_id: ^host_id},
                                                opts ->
      assert [Trento.ChecksScheduling.Projections.TargetChecksIntervalProjector] ==
               Keyword.fetch!(opts, :consistency)

      {:error, :host_not_registered}
    end)

    assert {:error, :not_found} == put_schedule(host_id, %{interval: "1h"})
  end

  test "should answer with the change saved while the read model is late", %{host_id: host_id} do
    expect(Trento.Commanded.Mock, :dispatch, fn _, _ -> {:error, :consistency_timeout} end)

    assert {:ok, %{interval: "1h", effective_interval: "1h"}} =
             put_schedule(host_id, %{interval: "1h"})
  end

  test "should handle clusters" do
    %{id: cluster_id} = insert(:cluster)

    assert {:ok, %{interval: "1w"}} =
             ChecksScheduling.update_target_schedule(
               :cluster,
               cluster_id,
               %{interval: "1w"},
               DateService.Mock
             )

    assert {:ok, %{interval: "1w"}} =
             ChecksScheduling.get_target_schedule(:cluster, cluster_id, DateService.Mock)

    expect(Trento.Commanded.Mock, :dispatch, fn %ChangeClusterChecksInterval{}, _ ->
      {:error, :cluster_not_registered}
    end)

    assert {:error, :not_found} ==
             ChecksScheduling.update_target_schedule(
               :cluster,
               cluster_id,
               %{interval: "1h"},
               DateService.Mock
             )
  end
end
