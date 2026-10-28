# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Commands.CompleteScheduledRun do
  @moduledoc """
  Record the outcome of the run of an occurrence: the operation was
  requested, or the request failed because the target is gone, the operation
  policies failed or a maintenance window forbids operations on the target.
  """

  @required_fields [:schedule_id, :run_at, :outcome, :completed_at]

  use Trento.Support.Command

  alias Trento.Operations.ValueObjects.PolicyError

  defcommand do
    field :schedule_id, Ecto.UUID
    field :run_at, :utc_datetime_usec
    field :outcome, Ecto.Enum, values: [:requested, :failed]
    field :reason, Ecto.Enum, values: [:policies, :target_not_found, :maintenance_window]
    embeds_many :errors, PolicyError
    field :completed_at, :utc_datetime_usec
  end

  def changeset(command, params) do
    changeset = super(command, params)

    case get_field(changeset, :outcome) do
      :failed -> validate_required(changeset, [:reason])
      _ -> changeset
    end
  end
end
