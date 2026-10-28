# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule TrentoWeb.V1.OperationScheduleParamsTest do
  use ExUnit.Case, async: true

  alias TrentoWeb.V1.OperationScheduleParams

  test "should accept the params of the immediate request of each operation" do
    host_id = UUID.uuid4()

    for {operation, params, expected} <- [
          {"reboot", %{}, %{}},
          {"reboot", nil, %{}},
          {"cluster_maintenance_change", %{"maintenance" => true}, %{maintenance: true}},
          {"sap_system_stop", %{"instance_type" => "all"}, %{instance_type: "all"}},
          {"database_start", %{"site" => "Site1", "timeout" => 300},
           %{site: "Site1", timeout: 300}},
          {"sap_instance_start", %{"host_id" => host_id, "instance_number" => "00"},
           %{host_id: host_id, instance_number: "00"}}
        ] do
      assert {:ok, expected} == OperationScheduleParams.cast(operation, params)
    end
  end

  test "should refuse params that the immediate request refuses" do
    for {operation, params} <- [
          {"reboot", %{"unexpected" => true}},
          {"cluster_maintenance_change", %{}},
          {"sap_instance_stop", %{"timeout" => 300}},
          {"database_stop", %{"timeout" => "soon"}}
        ] do
      assert {:error, {:invalid_params, [_ | _]}} =
               OperationScheduleParams.cast(operation, params)
    end
  end
end
