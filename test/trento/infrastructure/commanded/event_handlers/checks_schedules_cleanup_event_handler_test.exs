# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Infrastructure.Commanded.EventHandlers.ChecksSchedulesCleanupEventHandlerTest do
  use ExUnit.Case, async: true
  use Trento.DataCase

  alias Trento.ChecksScheduling.ExecutionRequest
  alias Trento.Clusters.Events.ClusterDeregistered
  alias Trento.Hosts.Events.HostDeregistered
  alias Trento.Infrastructure.Commanded.EventHandlers.ChecksSchedulesCleanupEventHandler

  test "should remove the last periodic request of a deregistered host or cluster" do
    [host_id, cluster_id, kept_id] = Enum.map(1..3, fn _ -> UUID.uuid4() end)

    for {target_id, target_type} <- [
          {host_id, "host"},
          {cluster_id, "cluster"},
          {kept_id, "host"}
        ] do
      Repo.insert!(%ExecutionRequest{
        target_id: target_id,
        target_type: target_type,
        last_requested_at: DateTime.utc_now()
      })
    end

    assert :ok ==
             ChecksSchedulesCleanupEventHandler.handle(
               %HostDeregistered{host_id: host_id, deregistered_at: DateTime.utc_now()},
               %{}
             )

    assert :ok ==
             ChecksSchedulesCleanupEventHandler.handle(
               %ClusterDeregistered{cluster_id: cluster_id, deregistered_at: DateTime.utc_now()},
               %{}
             )

    assert [%ExecutionRequest{target_id: ^kept_id}] = Repo.all(ExecutionRequest)
  end
end
