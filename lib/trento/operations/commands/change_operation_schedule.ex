# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Commands.ChangeOperationSchedule do
  @moduledoc """
  Replace the params and the timing of an operation schedule.

  `requested_at` is when the change is requested: a new start must come after
  it, while an ongoing periodic schedule can keep its start.
  """

  @required_fields [:schedule_id, :params, :starts_at, :timezone, :requested_at]

  use Trento.Support.Command

  alias Trento.Operations.ValueObjects.{OperationParams, Recurrence}

  defcommand do
    field :schedule_id, Ecto.UUID
    embeds_one :params, OperationParams
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    embeds_one :recurrence, Recurrence
    field :requested_at, :utc_datetime_usec
  end

  def changeset(command, params) do
    command
    |> super(params)
    |> validate_change(:timezone, fn :timezone, timezone ->
      if Tzdata.zone_exists?(timezone), do: [], else: [timezone: "is not a valid timezone"]
    end)
  end
end
