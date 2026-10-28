# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Infrastructure.Commanded.EventHandlers.OperationSchedulesCleanupEventHandler do
  @moduledoc """
  Cancels the operation schedules of a host, cluster, SAP system or database
  that is deregistered, and the SAP instance schedules of a deregistered
  instance or host, correlated to the clean up that removed them.

  It starts from the current events: a deregistration before the handler
  existed had no schedules to cancel. Handling an event again is harmless,
  the schedules cancelled already are skipped, so a failure is retried a few
  times before the event is skipped.
  """

  use Commanded.Event.Handler,
    application: Trento.Commanded,
    name: "operation_schedules_cleanup_event_handler",
    start_from: :current

  use Trento.Support.EventHandlerFailureContext,
    max_retries: 3,
    skip: true

  alias Trento.Clusters.Events.ClusterDeregistered
  alias Trento.Databases.Events.DatabaseDeregistered
  alias Trento.Hosts.Events.HostDeregistered
  alias Trento.Operations.Schedules
  alias Trento.SapSystems.Events.{ApplicationInstanceDeregistered, SapSystemDeregistered}

  def handle(%HostDeregistered{host_id: id}, metadata) do
    with :ok <- Schedules.cancel_instance_schedules([host_id: id], cause(metadata)) do
      Schedules.cancel_target_schedules(id, cause(metadata))
    end
  end

  def handle(%ClusterDeregistered{cluster_id: id}, metadata),
    do: Schedules.cancel_target_schedules(id, cause(metadata))

  def handle(%SapSystemDeregistered{sap_system_id: id}, metadata),
    do: Schedules.cancel_target_schedules(id, cause(metadata))

  def handle(%DatabaseDeregistered{database_id: id}, metadata),
    do: Schedules.cancel_target_schedules(id, cause(metadata))

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
      cause(metadata)
    )
  end

  # The cancellations are caused by the deregistration event, in its correlation
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
