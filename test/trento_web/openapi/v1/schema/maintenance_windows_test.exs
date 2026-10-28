# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule TrentoWeb.OpenApi.V1.Schema.MaintenanceWindowsTest do
  use ExUnit.Case, async: true

  import OpenApiSpex.TestAssertions

  alias OpenApiSpex.{Cast, Components, Info, OpenApi}

  alias TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.{
    BulkCreateMaintenanceWindowsRequest,
    BulkMaintenanceWindows,
    CreateMaintenanceWindowRequest,
    MaintenanceWindow,
    MaintenanceWindowCollection,
    Occurrence,
    UpdateMaintenanceWindowRequest
  }

  alias TrentoWeb.OpenApi.V1.Schema.Scheduling.Recurrence

  @schemas [
    BulkCreateMaintenanceWindowsRequest,
    BulkMaintenanceWindows,
    CreateMaintenanceWindowRequest,
    MaintenanceWindow,
    MaintenanceWindowCollection,
    Occurrence,
    Recurrence,
    UpdateMaintenanceWindowRequest
  ]

  setup_all do
    spec =
      OpenApiSpex.resolve_schema_modules(%OpenApi{
        info: %Info{title: "maintenance windows contract", version: "1"},
        paths: %{},
        components: %Components{
          schemas: Map.new(@schemas, &{&1.schema().title, &1.schema()})
        }
      })

    %{spec: spec}
  end

  defp window(overrides \\ %{}) do
    Map.merge(
      %{
        target_type: "sap_system",
        target_id: UUID.uuid4(),
        starts_at: "2026-11-07T22:00:00Z",
        timezone: "Etc/UTC",
        duration_minutes: 60,
        recurrence: nil,
        forbids: ["operations"]
      },
      overrides
    )
  end

  test "should validate the example of every schema", %{spec: spec} do
    for module <- @schemas, example = module.schema().example, not is_nil(example) do
      assert_schema(example, module.schema().title, spec)
    end
  end

  test "should accept a one-time window on every target type", %{spec: spec} do
    for target_type <- ~w(host cluster database sap_system) do
      assert_schema(window(%{target_type: target_type}), "CreateMaintenanceWindowRequestV1", spec)
    end
  end

  test "should refuse values outside the contract", %{spec: spec} do
    for value <- [
          window(%{target_type: "application_instance"}),
          window(%{forbids: []}),
          window(%{forbids: ["discovery"]}),
          window(%{duration_minutes: 0}),
          window(%{duration_minutes: 44_641})
        ] do
      schema = spec.components.schemas["CreateMaintenanceWindowRequestV1"]
      assert {:error, _} = Cast.cast(schema, value, spec.components.schemas)
    end
  end
end
