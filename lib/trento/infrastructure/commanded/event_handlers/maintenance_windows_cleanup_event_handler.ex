# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Infrastructure.Commanded.EventHandlers.MaintenanceWindowsCleanupEventHandler do
  @moduledoc """
  Deletes the maintenance windows of a host, cluster, database or SAP system
  that is deregistered, correlated to the clean up that removed it.

  It starts from the current events: a deregistration before the handler
  existed had no windows to delete.
  """

  use Commanded.Event.Handler,
    application: Trento.Commanded,
    name: "maintenance_windows_cleanup_event_handler",
    start_from: :current

  alias Trento.Clusters.Events.ClusterDeregistered
  alias Trento.Databases.Events.DatabaseDeregistered
  alias Trento.Hosts.Events.HostDeregistered
  alias Trento.MaintenanceWindows
  alias Trento.SapSystems.Events.SapSystemDeregistered

  def handle(%HostDeregistered{host_id: id}, metadata), do: delete(id, metadata)
  def handle(%ClusterDeregistered{cluster_id: id}, metadata), do: delete(id, metadata)
  def handle(%DatabaseDeregistered{database_id: id}, metadata), do: delete(id, metadata)
  def handle(%SapSystemDeregistered{sap_system_id: id}, metadata), do: delete(id, metadata)

  defp delete(target_id, metadata),
    do: MaintenanceWindows.delete_target_windows(target_id, Map.get(metadata, :correlation_id))
end
