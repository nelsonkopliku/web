# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Infrastructure.Commanded.EventHandlers.MaintenanceWindowsCleanupEventHandler do
  @moduledoc """
  Deletes the maintenance windows of a host, cluster, database or SAP system
  that is deregistered, correlated to the clean up that removed it.

  It starts from the current events: a deregistration before the handler
  existed had no windows to delete. Handling an event again is harmless, the
  windows deleted already are skipped, so a failure is retried a few times
  before the event is skipped.
  """

  use Commanded.Event.Handler,
    application: Trento.Commanded,
    name: "maintenance_windows_cleanup_event_handler",
    start_from: :current

  use Trento.Support.EventHandlerFailureContext,
    max_retries: 3,
    skip: true

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
    do: MaintenanceWindows.delete_target_windows(target_id, cause(metadata))

  # The deletions are caused by the deregistration event, in its correlation
  defp cause(metadata) do
    Enum.reject(
      [
        correlation_id: Map.get(metadata, :correlation_id),
        causation_id: Map.get(metadata, :event_id)
      ],
      fn {_, id} -> is_nil(id) end
    )
  end
end
