# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule TrentoWeb.V1.OperationScheduleController do
  use TrentoWeb, :controller
  use OpenApiSpex.ControllerSpecs
  use Trento.AI.ControllerSpecs

  alias Trento.Operations.{OperationSchedule, Schedules}
  alias TrentoWeb.OpenApi.V1.Schema
  alias TrentoWeb.OpenApi.V1.Schema.Scheduling
  alias TrentoWeb.V1.OperationScheduleParams

  plug TrentoWeb.Plugs.LoadUserPlug
  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  plug Bodyguard.Plug.Authorize,
    policy: Trento.Operations.SchedulesPolicy,
    action: {Phoenix.Controller, :action_name},
    user: {Pow.Plug, :current_user},
    params: {__MODULE__, :get_policy_resource},
    fallback: TrentoWeb.FallbackController

  action_fallback TrentoWeb.FallbackController

  @schedule_id_param [
    id: [
      in: :path,
      required: true,
      description: "Id of the operation schedule.",
      schema: %OpenApiSpex.Schema{
        type: :string,
        format: :uuid,
        example: "0c7a2e5c-2f5e-4d0e-9c3e-6a1f5b7d9e21"
      }
    ]
  ]

  operation :index,
    summary: "List operation schedules.",
    description:
      "Lists the operation schedules of a target, or of several targets for one operation, the next one first.",
    tags: ["Operations", "MCP"],
    parameters: [
      target_id: [
        in: :query,
        required: false,
        description: "Host, cluster, SAP system or database id.",
        schema: %OpenApiSpex.Schema{
          type: :string,
          format: :uuid,
          example: "e1e8a1d1-0a2b-4c3d-8e4f-5a6b7c8d9e0f"
        }
      ],
      target_ids: [
        in: :query,
        required: false,
        style: :form,
        explode: false,
        description:
          "Comma separated host, cluster, SAP system or database ids, to tell whether an operation is already scheduled on any of them.",
        schema: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{type: :string, format: :uuid},
          maxItems: 500
        }
      ],
      operation: [
        in: :query,
        required: false,
        description: "Only the schedules of this operation.",
        schema: %OpenApiSpex.Schema{type: :string, example: "reboot"}
      ]
    ],
    responses: [
      ok: {"Operation schedules.", "application/json", Scheduling.OperationScheduleCollection},
      unauthorized: Schema.Unauthorized.response(),
      unprocessable_entity: Schema.UnprocessableEntity.response()
    ]

  ai_tool :operation_schedules_list, display_text: "List operation schedules"

  def index(conn, params) do
    target_ids = Map.get(params, :target_ids) || List.wrap(Map.get(params, :target_id))

    case target_ids do
      [] ->
        {:error, :missing_target}

      target_ids ->
        schedules =
          Schedules.list_schedules(target_ids, operation: Map.get(params, :operation))

        render(conn, :operation_schedules, schedules: schedules)
    end
  end

  operation :create,
    summary: "Schedule an operation.",
    description:
      "Schedules an operation once or periodically. The params are the ones of the immediate request of the operation. The schedule is saved even when the operation policies fail now: they come back as warnings and run again when the schedule is due.",
    tags: ["Operations"],
    request_body: {"Schedule.", "application/json", Scheduling.CreateOperationScheduleRequest},
    responses: [
      created: {"Saved schedule.", "application/json", Scheduling.OperationSchedule},
      unauthorized: Schema.Unauthorized.response(),
      forbidden: Schema.Forbidden.response(),
      not_found: Schema.NotFound.response(),
      unprocessable_entity: Schema.UnprocessableEntity.response()
    ]

  def create(conn, _) do
    attrs = OpenApiSpex.body_params(conn)
    %{username: username} = Pow.Plug.current_user(conn)

    with {:ok, params} <- OperationScheduleParams.cast(attrs.operation, Map.get(attrs, :params)),
         {:ok, schedule, warnings} <-
           Schedules.create_schedule(%{attrs | params: params}, username) do
      conn
      |> put_status(:created)
      |> render(:operation_schedule, schedule: schedule, warnings: warnings)
    end
  end

  operation :update,
    summary: "Change an operation schedule.",
    description:
      "Replaces the params and the timing of an operation schedule. The occurrence count restarts. An ongoing periodic schedule can keep its start: it continues with its next occurrence.",
    tags: ["Operations"],
    parameters: @schedule_id_param,
    request_body:
      {"New timing and params.", "application/json", Scheduling.UpdateOperationScheduleRequest},
    responses: [
      ok: {"Changed schedule.", "application/json", Scheduling.OperationSchedule},
      unauthorized: Schema.Unauthorized.response(),
      forbidden: Schema.Forbidden.response(),
      not_found: Schema.NotFound.response(),
      unprocessable_entity: Schema.UnprocessableEntity.response()
    ]

  def update(conn, %{id: schedule_id}) do
    attrs = OpenApiSpex.body_params(conn)
    %{username: username} = Pow.Plug.current_user(conn)

    with {:ok, %OperationSchedule{operation: operation}} <- Schedules.get_schedule(schedule_id),
         {:ok, params} <- OperationScheduleParams.cast(operation, Map.get(attrs, :params)),
         {:ok, schedule, warnings} <-
           Schedules.update_schedule(schedule_id, Map.put(attrs, :params, params), username) do
      render(conn, :operation_schedule, schedule: schedule, warnings: warnings)
    end
  end

  operation :delete,
    summary: "Cancel an operation schedule.",
    description:
      "Cancels an operation schedule: it no longer runs. An operation already running is not affected.",
    tags: ["Operations"],
    parameters: @schedule_id_param,
    responses: [
      no_content: "The schedule is cancelled.",
      unauthorized: Schema.Unauthorized.response(),
      forbidden: Schema.Forbidden.response(),
      not_found: Schema.NotFound.response()
    ]

  def delete(conn, %{id: schedule_id}) do
    %{username: username} = Pow.Plug.current_user(conn)

    with :ok <- Schedules.cancel_schedule(schedule_id, username) do
      send_resp(conn, :no_content, "")
    end
  end

  def get_policy_resource(%{private: %{phoenix_action: :create}} = conn) do
    %{target_type: target_type, operation: operation} = OpenApiSpex.body_params(conn)
    %{target_type: target_type, operation: operation}
  end

  def get_policy_resource(%{private: %{phoenix_action: action}, params: %{id: id}})
      when action in [:update, :delete] do
    case Schedules.get_schedule(id) do
      {:ok, schedule} -> schedule
      {:error, :not_found} -> nil
    end
  end

  def get_policy_resource(_), do: nil
end
