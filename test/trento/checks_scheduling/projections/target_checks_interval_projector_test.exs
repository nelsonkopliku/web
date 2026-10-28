# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling.Projections.TargetChecksIntervalProjectorTest do
  use ExUnit.Case
  use Trento.DataCase

  alias Trento.ChecksScheduling.Projections.{
    TargetChecksIntervalProjector,
    TargetChecksIntervalReadModel
  }

  alias Trento.Clusters.Cluster

  alias Trento.Clusters.Events.{
    ClusterChecksIntervalChanged,
    ClusterDeregistered,
    ClusterRolledUp
  }

  alias Trento.Hosts.Events.{HostChecksIntervalChanged, HostDeregistered, HostRolledUp}
  alias Trento.Hosts.Host
  alias Trento.ProjectorTestHelper

  @moduletag :integration

  defp project(event),
    do:
      ProjectorTestHelper.project(
        TargetChecksIntervalProjector,
        event,
        "target_checks_interval_projector"
      )

  defp intervals,
    do:
      TargetChecksIntervalReadModel
      |> Repo.all()
      |> Enum.map(&{&1.target_id, &1.target_type, &1.interval})
      |> Enum.sort()

  test "should project the interval of a host and a cluster, and remove it for the global one" do
    host_id = UUID.uuid4()
    cluster_id = UUID.uuid4()

    project(%HostChecksIntervalChanged{host_id: host_id, interval: "6h"})
    project(%ClusterChecksIntervalChanged{cluster_id: cluster_id, interval: "disabled"})

    assert Enum.sort([{host_id, "host", "6h"}, {cluster_id, "cluster", "disabled"}]) ==
             intervals()

    project(%HostChecksIntervalChanged{host_id: host_id, interval: "1w"})
    project(%ClusterChecksIntervalChanged{cluster_id: cluster_id, interval: nil})

    assert [{host_id, "host", "1w"}] == intervals()
  end

  test "should remove the interval of a deregistered host or cluster" do
    host_id = UUID.uuid4()
    cluster_id = UUID.uuid4()
    kept_id = UUID.uuid4()

    project(%HostChecksIntervalChanged{host_id: host_id, interval: "6h"})
    project(%HostChecksIntervalChanged{host_id: kept_id, interval: "6h"})
    project(%ClusterChecksIntervalChanged{cluster_id: cluster_id, interval: "1h"})

    project(%HostDeregistered{host_id: host_id, deregistered_at: DateTime.utc_now()})
    project(%ClusterDeregistered{cluster_id: cluster_id, deregistered_at: DateTime.utc_now()})

    assert [{kept_id, "host", "6h"}] == intervals()
  end

  test "should take the interval from the snapshot of a roll-up" do
    host_id = UUID.uuid4()
    deregistered_id = UUID.uuid4()
    cluster_id = UUID.uuid4()

    project(%HostChecksIntervalChanged{host_id: deregistered_id, interval: "6h"})

    project(%HostRolledUp{
      host_id: host_id,
      snapshot: %Host{host_id: host_id, checks_interval: "12h"}
    })

    project(%HostRolledUp{
      host_id: deregistered_id,
      snapshot: %Host{
        host_id: deregistered_id,
        checks_interval: "6h",
        deregistered_at: DateTime.utc_now()
      }
    })

    project(%ClusterRolledUp{
      cluster_id: cluster_id,
      snapshot: %Cluster{cluster_id: cluster_id, checks_interval: "24h"}
    })

    assert Enum.sort([{host_id, "host", "12h"}, {cluster_id, "cluster", "24h"}]) == intervals()
  end
end
