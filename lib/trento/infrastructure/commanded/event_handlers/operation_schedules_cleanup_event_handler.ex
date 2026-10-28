# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Infrastructure.Commanded.EventHandlers.OperationSchedulesCleanupEventHandler do
  @moduledoc """
  Cancels the operation schedules of a host, cluster, SAP system or database
  that is deregistered, and the SAP instance schedules of a deregistered
  instance or host, correlated to the clean up that removed them.

  It starts from the current events: a deregistration before the handler
  existed had no schedules to cancel.
  """

  use Commanded.Event.Handler,
    application: Trento.Commanded,
    name: "operation_schedules_cleanup_event_handler",
    start_from: :current

  alias Trento.Clusters.Events.ClusterDeregistered
  alias Trento.Databases.Events.DatabaseDeregistered
  alias Trento.Hosts.Events.HostDeregistered
  alias Trento.Operations.Schedules
  alias Trento.SapSystems.Events.{ApplicationInstanceDeregistered, SapSystemDeregistered}

  def handle(%HostDeregistered{host_id: id}, metadata) do
    Schedules.cancel_instance_schedules([host_id: id], correlation_id(metadata))
    cancel(id, metadata)
  end

  def handle(%ClusterDeregistered{cluster_id: id}, metadata), do: cancel(id, metadata)
  def handle(%SapSystemDeregistered{sap_system_id: id}, metadata), do: cancel(id, metadata)
  def handle(%DatabaseDeregistered{database_id: id}, metadata), do: cancel(id, metadata)

  def handle(
        %ApplicationInstanceDeregistered{
          sap_system_id: sap_system_id,
          host_id: host_id,
          instance_number: instance_number
        },
        metadata
      ) do
    Schedules.cancel_instance_schedules(
      [sap_system_id: sap_system_id, host_id: host_id, instance_number: instance_number],
      correlation_id(metadata)
    )
  end

  defp cancel(target_id, metadata),
    do: Schedules.cancel_target_schedules(target_id, correlation_id(metadata))

  defp correlation_id(metadata), do: Map.get(metadata, :correlation_id)
end
