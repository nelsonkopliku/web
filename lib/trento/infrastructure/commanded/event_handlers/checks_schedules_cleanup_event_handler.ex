# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Infrastructure.Commanded.EventHandlers.ChecksSchedulesCleanupEventHandler do
  @moduledoc """
  Removes the checks execution settings of a host or cluster that is
  deregistered.

  It starts from the current events: a deregistration before the handler
  existed had no settings to remove.
  """

  use Commanded.Event.Handler,
    application: Trento.Commanded,
    name: "checks_schedules_cleanup_event_handler",
    start_from: :current

  alias Trento.ChecksScheduling
  alias Trento.Clusters.Events.ClusterDeregistered
  alias Trento.Hosts.Events.HostDeregistered

  def handle(%HostDeregistered{host_id: host_id}, _),
    do: ChecksScheduling.delete_target_schedule(host_id)

  def handle(%ClusterDeregistered{cluster_id: cluster_id}, _),
    do: ChecksScheduling.delete_target_schedule(cluster_id)
end
