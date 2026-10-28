# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule TrentoWeb.V1.MaintenanceWindowController do
  use TrentoWeb, :controller
  use OpenApiSpex.ControllerSpecs
  use Trento.AI.ControllerSpecs

  alias Trento.MaintenanceWindows
  alias TrentoWeb.OpenApi.V1.Schema
  alias TrentoWeb.OpenApi.V1.Schema.MaintenanceWindows, as: MaintenanceWindowsSchema

  require Trento.MaintenanceWindows.Enums.TargetType, as: TargetType

  plug TrentoWeb.Plugs.LoadUserPlug

  plug Bodyguard.Plug.Authorize,
    policy: Trento.MaintenanceWindows.Policy,
    action: {Phoenix.Controller, :action_name},
    user: {Pow.Plug, :current_user},
    fallback: TrentoWeb.FallbackController

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback TrentoWeb.FallbackController

  @window_id_param [
    id: [
      in: :path,
      required: true,
      description: "Id of the maintenance window.",
      schema: %OpenApiSpex.Schema{
        type: :string,
        format: :uuid,
        example: "8ef1c2d3-7a6b-4c5d-9e0f-1a2b3c4d5e6f"
      }
    ]
  ]

  operation :index,
    summary: "List the maintenance windows of a target.",
    description:
      "Lists the maintenance windows that cover a target with an ongoing or upcoming occurrence: its own windows and the ones it inherits from the targets that cover it, active ones first.",
    tags: ["Maintenance Windows", "MCP"],
    parameters: [
      target_type: [
        in: :query,
        required: true,
        description: "Type of the target.",
        schema: %OpenApiSpex.Schema{
          type: :string,
          enum: Enum.map(TargetType.values(), &Atom.to_string/1)
        }
      ],
      target_id: [
        in: :query,
        required: true,
        description: "Id of the host, cluster, database or SAP system.",
        schema: %OpenApiSpex.Schema{
          type: :string,
          format: :uuid,
          example: "d59523fc-0497-4b1e-9fdd-14aa7cda77f1"
        }
      ]
    ],
    responses: [
      ok:
        {"Maintenance windows of the target.", "application/json",
         MaintenanceWindowsSchema.MaintenanceWindowCollection},
      unauthorized: Schema.Unauthorized.response(),
      unprocessable_entity: Schema.UnprocessableEntity.response()
    ]

  ai_tool :maintenance_windows_list, display_text: "List the maintenance windows of a target"

  def index(conn, %{target_type: target_type, target_id: target_id}) do
    render(conn, :maintenance_windows,
      maintenance_windows: MaintenanceWindows.list_covering_windows(target_type, target_id)
    )
  end

  operation :create,
    summary: "Schedule a maintenance window.",
    description:
      "Sets a one-time or periodic maintenance window on a registered target. During the window, Trento does not execute checks, or does not run operations, on the target and on the targets it covers.",
    tags: ["Maintenance Windows"],
    request_body:
      {"Maintenance window.", "application/json",
       MaintenanceWindowsSchema.CreateMaintenanceWindowRequest},
    responses: [
      created:
        {"Saved maintenance window.", "application/json",
         MaintenanceWindowsSchema.MaintenanceWindow},
      unauthorized: Schema.Unauthorized.response(),
      forbidden: Schema.Forbidden.response(),
      not_found: Schema.NotFound.response(),
      unprocessable_entity: Schema.UnprocessableEntity.response()
    ]

  def create(conn, _) do
    %{username: username} = Pow.Plug.current_user(conn)

    with {:ok, window} <-
           MaintenanceWindows.create_window(OpenApiSpex.body_params(conn), username) do
      conn
      |> put_status(:created)
      |> render(:maintenance_window, maintenance_window: MaintenanceWindows.own_window(window))
    end
  end

  operation :bulk_create,
    summary: "Schedule a maintenance window on several targets.",
    description:
      "Sets the same maintenance window on several registered targets of one type, one window per target with the same bulk_id, or none when one of them is refused. The windows are then changed and deleted one by one.",
    tags: ["Maintenance Windows"],
    request_body:
      {"Targets and maintenance window.", "application/json",
       MaintenanceWindowsSchema.BulkCreateMaintenanceWindowsRequest},
    responses: [
      created:
        {"Saved maintenance windows.", "application/json",
         MaintenanceWindowsSchema.BulkMaintenanceWindows},
      unauthorized: Schema.Unauthorized.response(),
      forbidden: Schema.Forbidden.response(),
      not_found: Schema.NotFound.response(),
      unprocessable_entity: Schema.UnprocessableEntity.response()
    ]

  def bulk_create(conn, _) do
    %{username: username} = Pow.Plug.current_user(conn)

    with {:ok, bulk_id, windows} <-
           MaintenanceWindows.create_bulk_windows(OpenApiSpex.body_params(conn), username) do
      conn
      |> put_status(:created)
      |> render(:bulk_maintenance_windows,
        bulk_id: bulk_id,
        maintenance_windows: Enum.map(windows, &MaintenanceWindows.own_window/1)
      )
    end
  end

  operation :update,
    summary: "Change a maintenance window.",
    description:
      "Replaces the timing and the forbidden actions of a maintenance window. The change applies at once, also to an ongoing window, which can keep its start.",
    tags: ["Maintenance Windows"],
    parameters: @window_id_param,
    request_body:
      {"New timing and forbidden actions.", "application/json",
       MaintenanceWindowsSchema.UpdateMaintenanceWindowRequest},
    responses: [
      ok:
        {"Changed maintenance window.", "application/json",
         MaintenanceWindowsSchema.MaintenanceWindow},
      unauthorized: Schema.Unauthorized.response(),
      forbidden: Schema.Forbidden.response(),
      not_found: Schema.NotFound.response(),
      unprocessable_entity: Schema.UnprocessableEntity.response()
    ]

  def update(conn, %{id: window_id}) do
    %{username: username} = Pow.Plug.current_user(conn)

    with {:ok, window} <-
           MaintenanceWindows.update_window(window_id, OpenApiSpex.body_params(conn), username) do
      render(conn, :maintenance_window, maintenance_window: MaintenanceWindows.own_window(window))
    end
  end

  operation :delete,
    summary: "Delete a maintenance window.",
    description: "Deletes a maintenance window: it no longer forbids anything.",
    tags: ["Maintenance Windows"],
    parameters: @window_id_param,
    responses: [
      no_content: "The maintenance window is deleted.",
      unauthorized: Schema.Unauthorized.response(),
      forbidden: Schema.Forbidden.response(),
      not_found: Schema.NotFound.response()
    ]

  def delete(conn, %{id: window_id}) do
    %{username: username} = Pow.Plug.current_user(conn)

    with :ok <- MaintenanceWindows.delete_window(window_id, username) do
      send_resp(conn, :no_content, "")
    end
  end
end
