# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Commands.ScheduleMaintenanceWindow do
  @moduledoc """
  Set a maintenance window on a target, once or periodically, from
  `starts_at` in the local time of `timezone`, forbidding checks executions,
  operations or both.

  `requested_at` is when the window is requested: the window must start
  after it.
  """

  @required_fields [
    :window_id,
    :target_type,
    :target_id,
    :starts_at,
    :timezone,
    :duration_minutes,
    :forbids,
    :requested_at
  ]

  use Trento.Support.Command

  require Trento.MaintenanceWindows.Enums.ForbiddenAction, as: ForbiddenAction
  require Trento.MaintenanceWindows.Enums.TargetType, as: TargetType

  alias Trento.MaintenanceWindows.Commands.Timing
  alias Trento.MaintenanceWindows.ValueObjects.Recurrence

  defcommand do
    field :window_id, Ecto.UUID
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    field :duration_minutes, :integer
    embeds_one :recurrence, Recurrence
    field :forbids, {:array, Ecto.Enum}, values: ForbiddenAction.values()
    field :bulk_id, Ecto.UUID
    field :requested_at, :utc_datetime_usec
  end

  def changeset(command, params) do
    command
    |> super(params)
    |> validate_inclusion(:target_type, Enum.map(TargetType.values(), &Atom.to_string/1))
    |> Timing.validate(params)
  end
end
