# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

# The maintenance windows contract. Every backend implementation serves these
# schemas, so the frontend does not depend on how windows are stored.

defmodule TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.Occurrence do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    %{
      title: "MaintenanceWindowOccurrenceV1",
      description: "One occurrence of a maintenance window.",
      type: :object,
      nullable: true,
      additionalProperties: false,
      properties: %{
        starts_at: %Schema{type: :string, format: :"date-time"},
        ends_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:starts_at, :ends_at],
      example: %{starts_at: "2026-11-07T22:00:00Z", ends_at: "2026-11-08T02:00:00Z"}
    },
    struct?: false
  )
end

defmodule TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.Common do
  @moduledoc false

  alias OpenApiSpex.Schema
  alias TrentoWeb.OpenApi.V1.Schema.Scheduling.Recurrence

  require Trento.MaintenanceWindows.Enums.ForbiddenAction, as: ForbiddenAction
  require Trento.MaintenanceWindows.Enums.TargetType, as: TargetType

  @spec target_type() :: Schema.t()
  def target_type,
    do: %Schema{
      type: :string,
      enum: Enum.map(TargetType.values(), &Atom.to_string/1),
      description: "Type of the target the window is set on."
    }

  @spec timing_properties() :: map()
  def timing_properties,
    do: %{
      starts_at: %Schema{
        type: :string,
        format: :"date-time",
        description: "Start of the first occurrence."
      },
      timezone: %Schema{
        type: :string,
        example: "Europe/Berlin",
        description: "Timezone of the recurrence."
      },
      duration_minutes: %Schema{
        type: :integer,
        minimum: 1,
        maximum: 44_640,
        description: "Duration of each occurrence, up to 31 days."
      },
      recurrence: recurrence(),
      forbids: %Schema{
        type: :array,
        items: %Schema{type: :string, enum: Enum.map(ForbiddenAction.values(), &Atom.to_string/1)},
        minItems: 1,
        uniqueItems: true,
        description: "Actions forbidden on the covered targets during the window."
      }
    }

  defp recurrence do
    %Schema{} = recurrence = Recurrence.schema()

    %{
      recurrence
      | description:
          "How the window repeats. Null for a one-time window. max_occurrences is not supported."
    }
  end

  @spec timing_example() :: map()
  def timing_example,
    do: %{
      starts_at: "2026-11-07T22:00:00Z",
      timezone: "Europe/Berlin",
      duration_minutes: 240,
      recurrence: %{frequency: "weekly", interval: 1, weekdays: [6], ends_on: nil},
      forbids: ["checks_execution", "operations"]
    }
end

defmodule TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.MaintenanceWindow do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.{Common, Occurrence}

  OpenApiSpex.schema(
    %{
      title: "MaintenanceWindowV1",
      description:
        "One-time or periodic time slot in which Trento does not execute checks, or does not run operations, on the targets the window covers.",
      type: :object,
      additionalProperties: false,
      properties:
        Map.merge(Common.timing_properties(), %{
          id: %Schema{type: :string, format: :uuid},
          target_type: Common.target_type(),
          target_id: %Schema{type: :string, format: :uuid},
          target_name: %Schema{
            type: :string,
            nullable: true,
            description: "Host name, cluster name or SID of the target the window is set on."
          },
          bulk_id: %Schema{type: :string, format: :uuid, nullable: true},
          created_by: %Schema{type: :string, nullable: true},
          inserted_at: %Schema{type: :string, format: :"date-time"},
          updated_at: %Schema{type: :string, format: :"date-time"},
          inherited: %Schema{
            type: :boolean,
            description:
              "True when the window is set on another target that covers the requested one."
          },
          active: %Schema{type: :boolean, description: "True during an occurrence."},
          current_occurrence: Occurrence,
          next_occurrence: Occurrence
        }),
      required: [
        :id,
        :target_type,
        :target_id,
        :target_name,
        :starts_at,
        :timezone,
        :duration_minutes,
        :recurrence,
        :forbids,
        :bulk_id,
        :created_by,
        :inserted_at,
        :updated_at,
        :inherited,
        :active,
        :current_occurrence,
        :next_occurrence
      ],
      example:
        Map.merge(Common.timing_example(), %{
          id: "8ef1c2d3-7a6b-4c5d-9e0f-1a2b3c4d5e6f",
          target_type: "cluster",
          target_id: "34a94290-2236-5e4d-8def-05beb32d14d4",
          target_name: "hana_cluster",
          bulk_id: nil,
          created_by: "admin",
          inserted_at: "2026-11-02T10:00:00Z",
          updated_at: "2026-11-02T10:00:00Z",
          inherited: false,
          active: false,
          current_occurrence: nil,
          next_occurrence: %{starts_at: "2026-11-07T21:00:00Z", ends_at: "2026-11-08T01:00:00Z"}
        })
    },
    struct?: false
  )
end

defmodule TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.MaintenanceWindowCollection do
  @moduledoc false

  require OpenApiSpex
  alias TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.MaintenanceWindow

  OpenApiSpex.schema(
    %{
      title: "MaintenanceWindowCollectionV1",
      description:
        "Maintenance windows that cover a target, set on it or inherited from the targets that cover it.",
      type: :array,
      items: MaintenanceWindow
    },
    struct?: false
  )
end

defmodule TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.CreateMaintenanceWindowRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.Common

  OpenApiSpex.schema(
    %{
      title: "CreateMaintenanceWindowRequestV1",
      description: "Maintenance window to set on a target.",
      type: :object,
      additionalProperties: false,
      properties:
        Map.merge(Common.timing_properties(), %{
          target_type: Common.target_type(),
          target_id: %Schema{type: :string, format: :uuid}
        }),
      required: [:target_type, :target_id, :starts_at, :timezone, :duration_minutes, :forbids],
      example:
        Map.merge(Common.timing_example(), %{
          target_type: "cluster",
          target_id: "34a94290-2236-5e4d-8def-05beb32d14d4"
        })
    },
    struct?: false
  )
end

defmodule TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.UpdateMaintenanceWindowRequest do
  @moduledoc false

  require OpenApiSpex
  alias TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.Common

  OpenApiSpex.schema(
    %{
      title: "UpdateMaintenanceWindowRequestV1",
      description: "New timing and forbidden actions of a maintenance window.",
      type: :object,
      additionalProperties: false,
      properties: Common.timing_properties(),
      required: [:starts_at, :timezone, :duration_minutes, :forbids],
      example: Common.timing_example()
    },
    struct?: false
  )
end

defmodule TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.BulkCreateMaintenanceWindowsRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.Common

  OpenApiSpex.schema(
    %{
      title: "BulkCreateMaintenanceWindowsRequestV1",
      description: "Maintenance window to set on several targets of one type.",
      type: :object,
      additionalProperties: false,
      properties:
        Map.merge(Common.timing_properties(), %{
          target_type: Common.target_type(),
          target_ids: %Schema{
            type: :array,
            items: %Schema{type: :string, format: :uuid},
            minItems: 1,
            maxItems: 500,
            uniqueItems: true
          }
        }),
      required: [:target_type, :target_ids, :starts_at, :timezone, :duration_minutes, :forbids],
      example:
        Map.merge(Common.timing_example(), %{
          target_type: "host",
          target_ids: [
            "d59523fc-0497-4b1e-9fdd-14aa7cda77f1",
            "c1a8c1a4-b9b4-4d2a-8f6e-3a4b5c6d7e8f"
          ]
        })
    },
    struct?: false
  )
end

defmodule TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.BulkMaintenanceWindows do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows.MaintenanceWindow

  OpenApiSpex.schema(
    %{
      title: "BulkMaintenanceWindowsV1",
      description: "Maintenance windows created by a bulk request, one per target.",
      type: :object,
      additionalProperties: false,
      properties: %{
        bulk_id: %Schema{type: :string, format: :uuid},
        maintenance_windows: %Schema{type: :array, items: MaintenanceWindow}
      },
      required: [:bulk_id, :maintenance_windows]
    },
    struct?: false
  )
end
