# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.MaintenanceWindowsPolicy do
  @moduledoc """
  Refuses an operation on a target that an ongoing maintenance window covers,
  when the window forbids operations.

  The targets of an operation are the resource it runs on and, for the
  operations that act on one host of a cluster or of a SAP system, that host
  too: a window on a host forbids every operation on it.
  """

  alias Trento.Clusters.Projections.ClusterReadModel
  alias Trento.Databases.Projections.DatabaseReadModel
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.MaintenanceWindows
  alias Trento.SapSystems.Projections.{ApplicationInstanceReadModel, SapSystemReadModel}
  alias Trento.Support.OperationsHelper

  @type target :: {String.t(), String.t()}

  @spec targets(struct(), map()) :: [target()]
  def targets(%HostReadModel{id: id}, _params), do: [{"host", id}]

  def targets(%ClusterReadModel{id: id}, params),
    do: [{"cluster", id} | host_param(params)]

  def targets(%ApplicationInstanceReadModel{sap_system_id: sap_system_id, host_id: host_id}, _),
    do: [{"sap_system", sap_system_id}, {"host", host_id}]

  def targets(%SapSystemReadModel{id: id}, _params), do: [{"sap_system", id}]
  def targets(%DatabaseReadModel{id: id}, _params), do: [{"database", id}]

  # A resource that no maintenance window can cover.
  def targets(_resource, _params), do: []

  @doc """
  Checks the maintenance windows of the targets of an operation.
  """
  @spec authorize([target()]) :: :ok | {:error, [OperationsHelper.forbidden_error()]}
  def authorize(targets) do
    targets
    |> Enum.flat_map(fn {target_type, target_id} ->
      case MaintenanceWindows.forbidding_window(target_type, target_id, :operations) do
        :none -> []
        {:ok, window, name, ends_at} -> [error(window, name, ends_at)]
      end
    end)
    |> Enum.uniq()
    |> case do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp error(window, name, ends_at) do
    OperationsHelper.build_error(
      "Operations are not allowed during the maintenance window of {0}, until #{Calendar.strftime(ends_at, "%Y-%m-%d %H:%M")} UTC",
      [
        %{
          id: window.target_id,
          label: name || window.target_id,
          type: String.to_existing_atom(window.target_type)
        }
      ]
    )
  end

  defp host_param(params) do
    case Map.get(params, :host_id) || Map.get(params, "host_id") do
      nil -> []
      host_id -> [{"host", host_id}]
    end
  end
end
