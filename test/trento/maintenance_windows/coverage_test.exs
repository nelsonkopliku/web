# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.CoverageTest do
  use ExUnit.Case, async: true
  use Trento.DataCase

  import Trento.Factory

  alias Trento.MaintenanceWindows.Coverage

  # A HANA cluster manages the PRD database on its two hosts. The PRD SAP
  # system uses that database, and an ASCS/ERS cluster manages its ASCS
  # instance. An application server runs on a host of no cluster.
  setup do
    hana_cluster =
      insert(:cluster,
        sap_instances: [build(:clustered_sap_instance, sid: "PRD", instance_number: "00")]
      )

    ascs_cluster =
      insert(:cluster,
        sap_instances: [build(:clustered_sap_instance, sid: "NWP", instance_number: "01")]
      )

    [hana_host_1, hana_host_2] = insert_list(2, :host, cluster_id: hana_cluster.id)
    ascs_host = insert(:host, cluster_id: ascs_cluster.id)
    app_host = insert(:host, cluster_id: nil)

    database = insert(:database)

    for host <- [hana_host_1, hana_host_2] do
      insert(:database_instance,
        database_id: database.id,
        host_id: host.id,
        sid: "PRD",
        instance_number: "00"
      )
    end

    sap_system = insert(:sap_system, database_id: database.id)

    insert(:application_instance,
      sap_system_id: sap_system.id,
      host_id: ascs_host.id,
      sid: "NWP",
      instance_number: "01"
    )

    insert(:application_instance,
      sap_system_id: sap_system.id,
      host_id: app_host.id,
      sid: "NWP",
      instance_number: "02"
    )

    %{
      hana_cluster: hana_cluster.id,
      ascs_cluster: ascs_cluster.id,
      hana_host: hana_host_1.id,
      ascs_host: ascs_host.id,
      app_host: app_host.id,
      database: database.id,
      sap_system: sap_system.id
    }
  end

  defp owners(target_type, target_id),
    do: target_type |> Coverage.owners(target_id) |> Enum.sort()

  test "a SAP system is covered by its own windows only", %{sap_system: sap_system} do
    assert [{"sap_system", sap_system}] == owners("sap_system", sap_system)
  end

  test "a database is covered by its windows and those of its SAP systems", t do
    assert Enum.sort([{"database", t.database}, {"sap_system", t.sap_system}]) ==
             owners("database", t.database)
  end

  test "a cluster is covered by the databases and SAP systems it manages", t do
    assert Enum.sort([
             {"cluster", t.hana_cluster},
             {"database", t.database},
             {"sap_system", t.sap_system}
           ]) == owners("cluster", t.hana_cluster)

    assert Enum.sort([{"cluster", t.ascs_cluster}, {"sap_system", t.sap_system}]) ==
             owners("cluster", t.ascs_cluster)
  end

  test "a host is covered by its cluster, its database and its SAP systems", t do
    assert Enum.sort([
             {"host", t.hana_host},
             {"cluster", t.hana_cluster},
             {"database", t.database},
             {"sap_system", t.sap_system}
           ]) == owners("host", t.hana_host)

    assert Enum.sort([
             {"host", t.ascs_host},
             {"cluster", t.ascs_cluster},
             {"sap_system", t.sap_system}
           ]) == owners("host", t.ascs_host)

    assert Enum.sort([{"host", t.app_host}, {"sap_system", t.sap_system}]) ==
             owners("host", t.app_host)
  end

  defp covered(target_type, target_id),
    do: target_type |> Coverage.covered(target_id) |> Enum.sort()

  test "a window covers the targets below its target", t do
    assert [{"host", t.app_host}] == covered("host", t.app_host)

    assert Enum.sort([{"cluster", t.ascs_cluster}, {"host", t.ascs_host}]) ==
             covered("cluster", t.ascs_cluster)

    hana_hosts =
      Trento.Hosts.Projections.HostReadModel
      |> Repo.all()
      |> Enum.filter(&(&1.cluster_id == t.hana_cluster))
      |> Enum.map(&{"host", &1.id})

    assert Enum.sort([{"database", t.database}, {"cluster", t.hana_cluster} | hana_hosts]) ==
             covered("database", t.database)

    assert Enum.sort(
             [
               {"sap_system", t.sap_system},
               {"database", t.database},
               {"cluster", t.hana_cluster},
               {"cluster", t.ascs_cluster},
               {"host", t.ascs_host},
               {"host", t.app_host}
             ] ++ hana_hosts
           ) == covered("sap_system", t.sap_system)
  end

  test "a cluster that manages no SAP resource covers its hosts only" do
    %{id: cluster_id} = insert(:cluster, sap_instances: [])
    %{id: host_id} = insert(:host, cluster_id: cluster_id)

    assert [{"cluster", cluster_id}] == owners("cluster", cluster_id)
    assert Enum.sort([{"host", host_id}, {"cluster", cluster_id}]) == owners("host", host_id)
  end

  test "deregistered targets cover nothing", t do
    Repo.update_all(Trento.Databases.Projections.DatabaseReadModel,
      set: [deregistered_at: DateTime.utc_now()]
    )

    refute {"database", t.database} in owners("host", t.hana_host)
    refute {"database", t.database} in owners("cluster", t.hana_cluster)
  end
end
