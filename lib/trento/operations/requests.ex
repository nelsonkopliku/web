# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Requests do
  @moduledoc """
  Checks and requests an operation on a target without an HTTP connection.

  The checks are the ones `TrentoWeb.Plugs.OperationsPolicyPlug` runs for an
  immediate request: the target is loaded with the same preloads and handed to
  the same operation policy. Schedules use it when they are created (to warn
  the user) and when they run.

  Targets are hosts, clusters, SAP systems and databases. SAP instance
  operations target the SAP system and name the instance with the `host_id`
  and `instance_number` params.

  "Another operation is already running" is not checked here: Wanda refuses
  the request and replies with OperationCompleted REQUEST_FAILED/ALREADY_RUNNING.
  """

  alias Trento.{Clusters, Databases, Hosts, SapSystems}

  alias Trento.Clusters.Projections.ClusterReadModel
  alias Trento.Databases.Projections.DatabaseReadModel
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.SapSystems.Projections.{ApplicationInstanceReadModel, SapSystemReadModel}
  alias Trento.Support.OperationsHelper
  alias Trento.Users.User

  alias Trento.Operations.{
    ApplicationInstancePolicy,
    ClusterPolicy,
    DatabasePolicy,
    HostPolicy,
    SapSystemPolicy,
    Targets
  }

  @type target_type :: :host | :cluster | :sap_system | :database

  @schedulable %{
    host: [:reboot],
    cluster: [:cluster_maintenance_change],
    sap_system: [:sap_system_start, :sap_system_stop, :sap_instance_start, :sap_instance_stop],
    database: [:database_start, :database_stop]
  }

  @params %{
    reboot: [],
    cluster_maintenance_change: [:maintenance, :resource_id, :node_id],
    sap_system_start: [:instance_type, :timeout],
    sap_system_stop: [:instance_type, :timeout],
    sap_instance_start: [:host_id, :instance_number, :timeout],
    sap_instance_stop: [:host_id, :instance_number, :timeout],
    database_start: [:site, :timeout],
    database_stop: [:site, :timeout]
  }

  @sap_instance_operations [:sap_instance_start, :sap_instance_stop]

  @spec schedulable_operations(target_type()) :: [atom()]
  def schedulable_operations(target_type), do: Map.get(@schedulable, target_type, [])

  @doc """
  Turns a target type and an operation given as strings into the atoms this
  module works with, when the operation can be scheduled on that target type.
  """
  @spec parse(String.t(), String.t()) :: {:ok, target_type(), atom()} | :error
  def parse(target_type, operation) do
    Enum.find_value(@schedulable, :error, fn {type, operations} ->
      if Atom.to_string(type) == target_type do
        Enum.find_value(operations, :error, fn op ->
          if Atom.to_string(op) == operation, do: {:ok, type, op}
        end)
      end
    end)
  end

  @spec schedulable?(atom(), atom()) :: boolean()
  def schedulable?(target_type, operation),
    do: operation in schedulable_operations(target_type)

  @doc """
  Keeps the params the operation accepts, with atom keys.
  """
  @spec cast_params(atom(), map()) :: map()
  def cast_params(operation, params) do
    @params
    |> Map.get(operation, [])
    |> Enum.reduce(%{}, fn key, acc ->
      case fetch_param(params, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  @doc """
  Runs the operation policies on the current state of the target.
  """
  @spec authorize(target_type(), String.t(), atom(), map()) ::
          :ok | {:error, :not_found} | {:error, :forbidden, [OperationsHelper.forbidden_error()]}
  def authorize(target_type, target_id, operation, params) do
    params = cast_params(operation, params)

    with {:ok, policy, resource} <- load(target_type, target_id, operation, params) do
      case policy.authorize_operation(operation, resource, params) do
        :ok -> :ok
        {:error, errors} -> {:error, :forbidden, errors}
      end
    end
  end

  @doc """
  Requests the operation when the policies pass. Returns the operation id.
  """
  @spec request(target_type(), String.t(), atom(), map()) ::
          {:ok, String.t()}
          | {:error, :not_found}
          | {:error, :forbidden, [OperationsHelper.forbidden_error()]}
          | {:error, any()}
  def request(target_type, target_id, operation, params) do
    params = cast_params(operation, params)

    with :ok <- authorize(target_type, target_id, operation, params) do
      do_request(target_type, target_id, operation, params)
    end
  end

  @doc """
  Tells whether the user holds the ability to request the operation.
  """
  @spec allowed?(User.t(), atom(), atom()) :: boolean()
  def allowed?(%User{} = user, target_type, operation) do
    schedulable?(target_type, operation) and
      authorize_user(user, target_type, operation)
  end

  defp authorize_user(user, :host, operation),
    do: Hosts.Policy.authorize(operation, user, HostReadModel)

  defp authorize_user(user, :cluster, operation),
    do: Clusters.Policy.authorize(operation, user, ClusterReadModel)

  defp authorize_user(user, :sap_system, operation) when operation in @sap_instance_operations,
    do: SapSystems.Policy.authorize(operation, user, ApplicationInstanceReadModel)

  defp authorize_user(user, :sap_system, operation),
    do: SapSystems.Policy.authorize(operation, user, SapSystemReadModel)

  defp authorize_user(user, :database, operation),
    do: Databases.Policy.authorize(operation, user, DatabaseReadModel)

  defp load(:host, host_id, _, _), do: found(Targets.host(host_id), HostPolicy)
  defp load(:cluster, cluster_id, _, _), do: found(Targets.cluster(cluster_id), ClusterPolicy)

  defp load(:sap_system, sap_system_id, operation, params)
       when operation in @sap_instance_operations do
    sap_system_id
    |> Targets.application_instance(Map.get(params, :host_id), Map.get(params, :instance_number))
    |> found(ApplicationInstancePolicy)
  end

  defp load(:sap_system, sap_system_id, _, _),
    do: found(Targets.sap_system(sap_system_id), SapSystemPolicy)

  defp load(:database, database_id, _, params),
    do: found(Targets.database(database_id, Map.get(params, :site)), DatabasePolicy)

  defp load(_, _, _, _), do: {:error, :not_found}

  defp found(nil, _), do: {:error, :not_found}
  defp found(resource, policy), do: {:ok, policy, resource}

  defp do_request(:host, host_id, operation, params),
    do: Hosts.request_operation(operation, host_id, params)

  defp do_request(:cluster, cluster_id, operation, params),
    do: Clusters.request_operation(operation, cluster_id, params)

  defp do_request(:sap_system, _, operation, params) when operation in @sap_instance_operations do
    {%{host_id: host_id, instance_number: instance_number}, params} =
      Map.split(params, [:host_id, :instance_number])

    SapSystems.request_instance_operation(operation, host_id, instance_number, params)
  end

  defp do_request(:sap_system, sap_system_id, operation, params),
    do: SapSystems.request_operation(operation, sap_system_id, params)

  defp do_request(:database, database_id, operation, params),
    do: Databases.request_operation(operation, database_id, params)

  defp fetch_param(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(params, Atom.to_string(key))
    end
  end
end
