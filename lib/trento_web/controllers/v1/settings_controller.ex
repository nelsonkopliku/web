defmodule TrentoWeb.V1.SettingsController do
  use TrentoWeb, :controller

  alias Trento.Installation

  alias TrentoWeb.OpenApi.V1.Schema

  use OpenApiSpex.ControllerSpecs

  operation :settings,
    summary: "Platform Settings",
    tags: ["Platform"],
    description: "Provides the Platform Settings for the current installation.",
    responses: [
      ok: {"Platform Settings", "application/json", Schema.Platform.Settings}
    ]

  @spec settings(Plug.Conn.t(), any) :: Plug.Conn.t()
  def settings(conn, _) do
    render(conn, "settings.json",
      settings: %{
        eula_accepted: Installation.eula_accepted?(),
        premium_subscription: Installation.premium?()
      }
    )
  end

  operation :accept_eula,
    summary: "Accept Eula",
    tags: ["Platform"],
    description: "Accepting EULA allows the end user to use the platform",
    responses: [
      ok:
        "EULA acceptance has been correctly registered and the user may continue using the platform"
    ]

  @spec accept_eula(Plug.Conn.t(), any) :: Plug.Conn.t()
  def accept_eula(conn, _) do
    :ok = Installation.accept_eula()

    json(conn, %{})
  end
end
