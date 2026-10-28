# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule TrentoWeb.V1.ChecksScheduleController do
  use TrentoWeb, :controller
  use OpenApiSpex.ControllerSpecs
  use Trento.AI.ControllerSpecs

  alias Trento.ChecksScheduling
  alias TrentoWeb.OpenApi.V1.Schema
  alias TrentoWeb.OpenApi.V1.Schema.Scheduling

  plug TrentoWeb.Plugs.LoadUserPlug

  plug Bodyguard.Plug.Authorize,
    policy: Trento.ChecksScheduling.Policy,
    action: {Phoenix.Controller, :action_name},
    user: {Pow.Plug, :current_user},
    fallback: TrentoWeb.FallbackController

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback TrentoWeb.FallbackController

  @host_id_param [
    id: [
      in: :path,
      required: true,
      description: "Id of the host.",
      schema: %OpenApiSpex.Schema{
        type: :string,
        format: :uuid,
        example: "d59523fc-0497-4b1e-9fdd-14aa7cda77f1"
      }
    ]
  ]

  @cluster_id_param [
    id: [
      in: :path,
      required: true,
      description: "Id of the cluster.",
      schema: %OpenApiSpex.Schema{
        type: :string,
        format: :uuid,
        example: "34a94290-2236-5e4d-8def-05beb32d14d4"
      }
    ]
  ]

  @show_responses [
    ok: {"Checks execution settings.", "application/json", Scheduling.ChecksSchedule},
    unauthorized: Schema.Unauthorized.response(),
    not_found: Schema.NotFound.response()
  ]

  @update_responses [
    ok: {"Checks execution settings.", "application/json", Scheduling.ChecksSchedule},
    unauthorized: Schema.Unauthorized.response(),
    forbidden: Schema.Forbidden.response(),
    not_found: Schema.NotFound.response(),
    unprocessable_entity: Schema.UnprocessableEntity.response()
  ]

  operation :show_host_checks_schedule,
    summary: "Get the checks execution interval of a host.",
    description:
      "Tells the interval of the periodic checks executions of the host, the global one it falls back to, and when the next execution runs.",
    tags: ["Checks", "MCP"],
    parameters: @host_id_param,
    responses: @show_responses

  ai_tool :checks_get_host_schedule, display_text: "Get the checks execution interval of a host"

  def show_host_checks_schedule(conn, %{id: id}), do: show(conn, :host, id)

  operation :update_host_checks_schedule,
    summary: "Change the checks execution interval of a host.",
    description:
      "Sets the interval of the periodic checks executions of the host. Null makes the host use the global interval again.",
    tags: ["Checks"],
    parameters: @host_id_param,
    request_body: {"Interval.", "application/json", Scheduling.UpdateChecksScheduleRequest},
    responses: @update_responses

  def update_host_checks_schedule(conn, %{id: id}), do: update(conn, :host, id)

  operation :show_cluster_checks_schedule,
    summary: "Get the checks execution interval of a cluster.",
    description:
      "Tells the interval of the periodic checks executions of the cluster, the global one it falls back to, and when the next execution runs.",
    tags: ["Checks", "MCP"],
    parameters: @cluster_id_param,
    responses: @show_responses

  ai_tool :checks_get_cluster_schedule,
    display_text: "Get the checks execution interval of a cluster"

  def show_cluster_checks_schedule(conn, %{id: id}), do: show(conn, :cluster, id)

  operation :update_cluster_checks_schedule,
    summary: "Change the checks execution interval of a cluster.",
    description:
      "Sets the interval of the periodic checks executions of the cluster. Null makes the cluster use the global interval again.",
    tags: ["Checks"],
    parameters: @cluster_id_param,
    request_body: {"Interval.", "application/json", Scheduling.UpdateChecksScheduleRequest},
    responses: @update_responses

  def update_cluster_checks_schedule(conn, %{id: id}), do: update(conn, :cluster, id)

  defp show(conn, target_type, id) do
    with {:ok, checks_schedule} <- ChecksScheduling.get_target_schedule(target_type, id) do
      render(conn, :checks_schedule, checks_schedule: checks_schedule)
    end
  end

  defp update(conn, target_type, id) do
    with {:ok, checks_schedule} <-
           ChecksScheduling.update_target_schedule(target_type, id, OpenApiSpex.body_params(conn)) do
      render(conn, :checks_schedule, checks_schedule: checks_schedule)
    end
  end
end
