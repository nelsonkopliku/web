# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Commands.ChangeMaintenanceWindow do
  @moduledoc """
  Replace the timing and the forbidden actions of a maintenance window.

  `requested_at` is when the change is requested: a new start must come
  after it, while an ongoing window can keep its start.
  """

  @required_fields [:window_id, :starts_at, :timezone, :duration_minutes, :forbids, :requested_at]

  use Trento.Support.Command

  require Trento.MaintenanceWindows.Enums.ForbiddenAction, as: ForbiddenAction

  alias Trento.MaintenanceWindows.Commands.Timing
  alias Trento.MaintenanceWindows.ValueObjects.Recurrence

  defcommand do
    field :window_id, Ecto.UUID
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    field :duration_minutes, :integer
    embeds_one :recurrence, Recurrence
    field :forbids, {:array, Ecto.Enum}, values: ForbiddenAction.values()
    field :requested_at, :utc_datetime_usec
  end

  def changeset(command, params) do
    command
    |> super(params)
    |> Timing.validate(params)
  end
end
