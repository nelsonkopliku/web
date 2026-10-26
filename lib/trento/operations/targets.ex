# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Targets do
  @moduledoc """
  Loads the target of an operation with what its operation policy needs.

  The operation controllers authorize immediate requests with these loaders,
  and `Trento.Operations.Requests` authorizes requests without an HTTP
  connection, such as scheduled ones, with the same loaders.
  """

  alias Trento.{Clusters, Databases, Repo, SapSystems}

  alias Trento.Clusters.Projections.ClusterReadModel
  alias Trento.Databases.Projections.DatabaseReadModel
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.SapSystems.Projections.{ApplicationInstanceReadModel, SapSystemReadModel}

  @spec host(String.t()) :: HostReadModel.t() | nil
  def host(host_id) do
    HostReadModel
    |> Repo.get(host_id)
    |> Repo.preload([:cluster, :application_instances, :database_instances])
  end

  @spec cluster(String.t()) :: ClusterReadModel.t() | nil
  def cluster(cluster_id) do
    cluster_id
    |> Clusters.get_cluster_by_id()
    |> Repo.preload(:hosts)
  end

  @doc """
  The cluster of a cluster host operation, nil when the host is not one of its hosts.
  """
  @spec cluster_with_host(String.t(), String.t()) :: ClusterReadModel.t() | nil
  def cluster_with_host(cluster_id, host_id) do
    cluster_id
    |> Clusters.get_cluster_by_id()
    |> Repo.preload(hosts: [:database_instances])
    |> case do
      %ClusterReadModel{hosts: hosts} = cluster ->
        if Enum.any?(hosts, &(&1.id == host_id)), do: cluster

      nil ->
        nil
    end
  end

  @spec application_instance(String.t(), String.t(), String.t()) ::
          ApplicationInstanceReadModel.t() | nil
  def application_instance(sap_system_id, host_id, instance_number) do
    instances = SapSystems.get_application_instances_by_id(sap_system_id)

    instances
    |> Enum.find(&match?(%{host_id: ^host_id, instance_number: ^instance_number}, &1))
    |> Repo.preload(
      sap_system: [:database, application_instances: fn _ -> instances end],
      host: :cluster
    )
  end

  @spec sap_system(String.t()) :: SapSystemReadModel.t() | nil
  def sap_system(sap_system_id) do
    sap_system_id
    |> SapSystems.get_sap_system_by_id()
    |> Repo.preload([:database_instances, [application_instances: [host: :cluster]]])
  end

  @doc """
  The database of a database operation, nil when the given site does not exist.
  """
  @spec database(String.t(), String.t() | nil) :: DatabaseReadModel.t() | nil
  def database(database_id, site \\ nil) do
    database_id
    |> Databases.get_database_by_id()
    |> Repo.preload(database_instances: [host: [:cluster]], sap_systems: [:application_instances])
    |> case do
      %DatabaseReadModel{database_instances: instances} = database when not is_nil(site) ->
        if Enum.any?(instances, &(&1.system_replication_site == site)), do: database

      database ->
        database
    end
  end
end
