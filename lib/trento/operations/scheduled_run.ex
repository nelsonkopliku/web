# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ScheduledRun do
  @moduledoc """
  An operation requested by a schedule: which occurrence of which schedule
  requested which operation. Wanda replies with the operation id only, so the
  run tells which schedule a reply belongs to, also after a one-time schedule
  is gone.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @fields [:operation_id, :schedule_id, :run_at, :target_type, :target_id, :operation, :params]

  @primary_key {:operation_id, Ecto.UUID, autogenerate: false}
  schema "scheduled_operation_runs" do
    field :schedule_id, Ecto.UUID
    field :run_at, :utc_datetime_usec
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :operation, :string
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, @fields)
    |> validate_required(@fields -- [:params])
    |> unique_constraint([:schedule_id, :run_at])
  end
end
