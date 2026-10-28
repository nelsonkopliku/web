# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling.Projections.TargetChecksExceptionWindowProjectorTest do
  use ExUnit.Case
  use Trento.DataCase

  alias Trento.ChecksScheduling.Projections.{
    TargetChecksExceptionWindowProjector,
    TargetChecksExceptionWindowReadModel
  }

  alias Trento.ChecksScheduling.ValueObjects.ExceptionWindow
  alias Trento.Clusters.Cluster

  alias Trento.Clusters.Events.{
    ClusterChecksExceptionWindowRemoved,
    ClusterChecksExceptionWindowSet,
    ClusterDeregistered,
    ClusterRolledUp
  }

  alias Trento.Hosts.Events.{HostChecksExceptionWindowSet, HostDeregistered, HostRolledUp}
  alias Trento.Hosts.Host
  alias Trento.ProjectorTestHelper

  @moduletag :integration

  @window %ExceptionWindow{
    starts_at: ~U[2026-11-07 22:00:00.000000Z],
    timezone: "Europe/Berlin",
    duration_minutes: 120,
    frequency: :weekly,
    interval: 1,
    weekdays: [6]
  }

  defp project(event),
    do:
      ProjectorTestHelper.project(
        TargetChecksExceptionWindowProjector,
        event,
        "target_checks_exception_window_projector"
      )

  defp windows do
    TargetChecksExceptionWindowReadModel
    |> Repo.all()
    |> Enum.map(&{&1.target_id, TargetChecksExceptionWindowReadModel.to_exception_window(&1)})
    |> Enum.sort()
  end

  test "should project the window of a host and a cluster, and remove it" do
    host_id = UUID.uuid4()
    cluster_id = UUID.uuid4()
    one_time = %ExceptionWindow{@window | frequency: nil, interval: nil, weekdays: nil}

    project(%HostChecksExceptionWindowSet{host_id: host_id, exception_window: @window})
    project(%ClusterChecksExceptionWindowSet{cluster_id: cluster_id, exception_window: @window})
    project(%ClusterChecksExceptionWindowSet{cluster_id: cluster_id, exception_window: one_time})

    assert Enum.sort([{host_id, @window}, {cluster_id, one_time}]) == windows()

    project(%ClusterChecksExceptionWindowRemoved{cluster_id: cluster_id})

    assert [{host_id, @window}] == windows()
  end

  test "should remove the window of a deregistered host or cluster" do
    host_id = UUID.uuid4()
    cluster_id = UUID.uuid4()

    project(%HostChecksExceptionWindowSet{host_id: host_id, exception_window: @window})
    project(%ClusterChecksExceptionWindowSet{cluster_id: cluster_id, exception_window: @window})
    project(%HostDeregistered{host_id: host_id, deregistered_at: DateTime.utc_now()})
    project(%ClusterDeregistered{cluster_id: cluster_id, deregistered_at: DateTime.utc_now()})

    assert [] == windows()
  end

  test "should take the window from the snapshot of a roll-up" do
    host_id = UUID.uuid4()
    cluster_id = UUID.uuid4()

    project(%HostRolledUp{
      host_id: host_id,
      snapshot: %Host{host_id: host_id, checks_exception_window: @window}
    })

    project(%ClusterChecksExceptionWindowSet{cluster_id: cluster_id, exception_window: @window})

    project(%ClusterRolledUp{
      cluster_id: cluster_id,
      snapshot: %Cluster{cluster_id: cluster_id, checks_exception_window: nil}
    })

    assert [{host_id, @window}] == windows()
  end
end
