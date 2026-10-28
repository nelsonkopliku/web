# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Support.Helpers.ChecksIntervalTestHelper do
  @moduledoc """
  Runs the checks execution interval and exception window commands through
  the Host and Cluster aggregates and their projectors in the test process,
  in place of the Commanded application. A change is read back from the read
  models the projectors write, without the event handlers of the application.
  """

  import Mox
  import Trento.Factory

  alias Trento.ChecksScheduling.Projections.{
    TargetChecksExceptionWindowProjector,
    TargetChecksIntervalProjector
  }

  alias Trento.Clusters.Cluster

  alias Trento.Clusters.Commands.{
    ChangeClusterChecksInterval,
    RemoveClusterChecksExceptionWindow,
    SetClusterChecksExceptionWindow
  }

  alias Trento.Hosts.Commands.{
    ChangeHostChecksInterval,
    RemoveHostChecksExceptionWindow,
    SetHostChecksExceptionWindow
  }

  alias Trento.Hosts.Host
  alias Trento.ProjectorTestHelper

  def stub_checks_interval_commands(_context \\ %{}) do
    {:ok, aggregates} = Agent.start_link(fn -> %{} end)

    stub(Trento.Commanded.Mock, :dispatch, fn command, _opts -> run(aggregates, command) end)

    :ok
  end

  defp run(aggregates, %command{host_id: host_id} = host_command)
       when command in [
              ChangeHostChecksInterval,
              SetHostChecksExceptionWindow,
              RemoveHostChecksExceptionWindow
            ],
       do: execute(aggregates, host_id, host_command, fn -> registered_host(host_id) end)

  defp run(aggregates, %command{cluster_id: cluster_id} = cluster_command)
       when command in [
              ChangeClusterChecksInterval,
              SetClusterChecksExceptionWindow,
              RemoveClusterChecksExceptionWindow
            ],
       do:
         execute(aggregates, cluster_id, cluster_command, fn -> registered_cluster(cluster_id) end)

  defp execute(aggregates, id, command, registered) do
    %aggregate{} = state = Agent.get(aggregates, &Map.get(&1, id)) || registered.()

    case aggregate.execute(state, command) do
      {:error, _} = error ->
        error

      events ->
        events = List.wrap(events)
        new_state = Enum.reduce(events, state, fn event, acc -> aggregate.apply(acc, event) end)
        Agent.update(aggregates, &Map.put(&1, id, new_state))

        for event <- events,
            {projector, name} <- [
              {TargetChecksIntervalProjector, "target_checks_interval_projector"},
              {TargetChecksExceptionWindowProjector, "target_checks_exception_window_projector"}
            ] do
          ProjectorTestHelper.project(projector, event, name)
        end

        :ok
    end
  end

  defp registered_host(host_id),
    do: Host.apply(%Host{}, build(:host_registered_event, host_id: host_id))

  defp registered_cluster(cluster_id),
    do: Cluster.apply(%Cluster{}, build(:cluster_registered_event, cluster_id: cluster_id))
end
