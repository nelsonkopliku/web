# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.TargetsTest do
  use ExUnit.Case, async: true
  use Trento.DataCase

  import Trento.Factory

  alias Trento.Operations.Targets

  test "should load a host with the data its operation policy needs" do
    %{id: cluster_id} = insert(:cluster)
    %{id: host_id} = insert(:host, cluster_id: cluster_id)

    assert %{
             id: ^host_id,
             cluster: %{id: ^cluster_id},
             application_instances: [],
             database_instances: []
           } =
             Targets.host(host_id)

    assert nil == Targets.host(UUID.uuid4())
  end

  test "should load the cluster of a cluster host operation only for one of its hosts" do
    %{id: cluster_id} = insert(:cluster)
    %{id: host_id} = insert(:host, cluster_id: cluster_id)
    %{id: other_host_id} = insert(:host)

    assert %{id: ^cluster_id, hosts: [%{id: ^host_id, database_instances: []}]} =
             Targets.cluster_with_host(cluster_id, host_id)

    assert nil == Targets.cluster_with_host(cluster_id, other_host_id)
    assert nil == Targets.cluster_with_host(UUID.uuid4(), host_id)
  end

  test "should load an application instance of a SAP system" do
    %{id: sap_system_id} = insert(:sap_system)
    %{id: host_id} = insert(:host)

    insert(:application_instance,
      sap_system_id: sap_system_id,
      host_id: host_id,
      instance_number: "00"
    )

    assert %{sap_system: %{id: ^sap_system_id}, host: %{id: ^host_id}} =
             Targets.application_instance(sap_system_id, host_id, "00")

    assert nil == Targets.application_instance(sap_system_id, host_id, "01")
  end

  test "should load a database, and refuse a site it does not have" do
    %{id: database_id} = insert(:database)

    insert(:database_instance,
      database_id: database_id,
      system_replication_site: "Site1"
    )

    assert %{id: ^database_id} = Targets.database(database_id)
    assert %{id: ^database_id} = Targets.database(database_id, "Site1")
    assert nil == Targets.database(database_id, "Site2")
  end
end
