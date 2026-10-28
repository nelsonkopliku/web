# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Coverage do
  @moduledoc """
  Which targets carry the maintenance windows that cover a target.

  A window covers the target it is set on and the targets below it:

  - a cluster covers its hosts
  - a database covers the cluster that manages it, the hosts of that cluster
    and its own hosts
  - a SAP system covers its database (as above), the cluster that manages its
    ASCS/ERS instances, the hosts of that cluster and its own hosts

  A cluster manages a database or SAP instance when its SAP resources name
  the SID and instance number of an instance running on one of its hosts.

  The coverage is resolved when it is asked, on the topology Trento knows at
  that moment: a host added to a cluster during a cluster window is covered by
  it. Deregistered targets cover nothing.
  """

  import Ecto.Query

  alias Trento.Clusters.Projections.ClusterReadModel
  alias Trento.Databases.Projections.{DatabaseInstanceReadModel, DatabaseReadModel}
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.Repo
  alias Trento.SapSystems.Projections.{ApplicationInstanceReadModel, SapSystemReadModel}

  @type target :: {String.t(), String.t()}

  defmacrop managed_by(cluster, sid, instance_number) do
    quote do
      fragment(
        "? @> jsonb_build_array(jsonb_build_object('sid', ?::text, 'instance_number', ?::text))",
        field(unquote(cluster), :sap_instances),
        unquote(sid),
        unquote(instance_number)
      )
    end
  end

  @doc """
  The targets whose windows cover the given target, the target included.
  """
  @spec owners(String.t(), String.t()) :: [target()]
  def owners("sap_system", sap_system_id), do: [{"sap_system", sap_system_id}]

  def owners("database", database_id),
    do: [{"database", database_id} | sap_systems_of_databases([database_id])]

  def owners("cluster", cluster_id) do
    databases = databases_managed_by(cluster_id)

    [{"cluster", cluster_id}]
    |> Kernel.++(Enum.map(databases, &{"database", &1}))
    |> Kernel.++(sap_systems_of_databases(databases))
    |> Kernel.++(Enum.map(sap_systems_managed_by(cluster_id), &{"sap_system", &1}))
    |> Enum.uniq()
  end

  def owners("host", host_id) do
    databases = databases_on_host(host_id)

    [{"host", host_id}]
    |> Kernel.++(Enum.map(databases, &{"database", &1}))
    |> Kernel.++(sap_systems_of_databases(databases))
    |> Kernel.++(Enum.map(sap_systems_on_host(host_id), &{"sap_system", &1}))
    |> Kernel.++(cluster_owners(host_id))
    |> Enum.uniq()
  end

  defp cluster_owners(host_id) do
    query =
      from h in HostReadModel,
        join: c in ClusterReadModel,
        on: c.id == h.cluster_id and is_nil(c.deregistered_at),
        where: h.id == ^host_id,
        select: c.id

    case Repo.one(query) do
      nil -> []
      cluster_id -> owners("cluster", cluster_id)
    end
  end

  defp databases_on_host(host_id) do
    Repo.all(
      from di in DatabaseInstanceReadModel,
        join: d in DatabaseReadModel,
        on: d.id == di.database_id and is_nil(d.deregistered_at),
        where: di.host_id == ^host_id,
        distinct: true,
        select: d.id
    )
  end

  defp sap_systems_on_host(host_id) do
    Repo.all(
      from ai in ApplicationInstanceReadModel,
        join: s in SapSystemReadModel,
        on: s.id == ai.sap_system_id and is_nil(s.deregistered_at),
        where: ai.host_id == ^host_id,
        distinct: true,
        select: s.id
    )
  end

  defp sap_systems_of_databases([]), do: []

  defp sap_systems_of_databases(database_ids) do
    Repo.all(
      from s in SapSystemReadModel,
        where: s.database_id in ^database_ids and is_nil(s.deregistered_at),
        select: s.id
    )
    |> Enum.map(&{"sap_system", &1})
  end

  defp databases_managed_by(cluster_id) do
    Repo.all(
      from di in DatabaseInstanceReadModel,
        join: h in HostReadModel,
        on: h.id == di.host_id and is_nil(h.deregistered_at),
        join: c in ClusterReadModel,
        on: c.id == h.cluster_id,
        join: d in DatabaseReadModel,
        on: d.id == di.database_id and is_nil(d.deregistered_at),
        where: c.id == ^cluster_id and managed_by(c, di.sid, di.instance_number),
        distinct: true,
        select: d.id
    )
  end

  defp sap_systems_managed_by(cluster_id) do
    Repo.all(
      from ai in ApplicationInstanceReadModel,
        join: h in HostReadModel,
        on: h.id == ai.host_id and is_nil(h.deregistered_at),
        join: c in ClusterReadModel,
        on: c.id == h.cluster_id,
        join: s in SapSystemReadModel,
        on: s.id == ai.sap_system_id and is_nil(s.deregistered_at),
        where: c.id == ^cluster_id and managed_by(c, ai.sid, ai.instance_number),
        distinct: true,
        select: s.id
    )
  end
end
