# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule TrentoWeb.V1.OperationScheduleParams do
  @moduledoc """
  Validates the params of a scheduled operation with the schema of the
  immediate request of that operation. SAP instance operations target the SAP
  system, so their params also name the instance.
  """

  alias OpenApiSpex.{Cast, Schema}

  alias TrentoWeb.OpenApi.V1.Schema.Operations.{
    ClusterMaintenanceChangeParams,
    DatabaseStartStopParams,
    SapInstanceStartStopParams,
    SapSystemStartStopParams
  }

  @no_params %Schema{type: :object, additionalProperties: false, properties: %{}}

  @instance_properties %{
    host_id: %Schema{type: :string, format: :uuid, description: "Host of the instance."},
    instance_number: %Schema{type: :string, description: "Number of the instance."}
  }

  @spec cast(String.t(), map()) :: {:ok, map()} | {:error, {:invalid_params, [Cast.Error.t()]}}
  def cast(operation, params) do
    case Cast.cast(schema(operation), params || %{}) do
      {:ok, cast_params} -> {:ok, cast_params}
      {:error, errors} -> {:error, {:invalid_params, errors}}
    end
  end

  defp schema("cluster_maintenance_change"), do: ClusterMaintenanceChangeParams.schema()

  defp schema(operation) when operation in ["sap_system_start", "sap_system_stop"],
    do: SapSystemStartStopParams.schema()

  defp schema(operation) when operation in ["database_start", "database_stop"],
    do: DatabaseStartStopParams.schema()

  defp schema(operation) when operation in ["sap_instance_start", "sap_instance_stop"] do
    %Schema{properties: properties, required: required} =
      instance_schema = SapInstanceStartStopParams.schema()

    %{
      instance_schema
      | properties: Map.merge(properties || %{}, @instance_properties),
        required: Enum.uniq((required || []) ++ [:host_id, :instance_number])
    }
  end

  defp schema(_), do: @no_params
end
