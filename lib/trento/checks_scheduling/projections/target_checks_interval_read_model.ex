# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling.Projections.TargetChecksIntervalReadModel do
  @moduledoc """
  The checks execution interval of a host or cluster that does not use the
  global one, projected from its events.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @derive {Jason.Encoder, except: [:__meta__, :__struct__]}
  @primary_key {:target_id, Ecto.UUID, autogenerate: false}
  schema "target_checks_intervals" do
    field :target_type, :string
    field :interval, :string

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t() | Ecto.Changeset.t(), map) :: Ecto.Changeset.t()
  def changeset(checks_interval, attrs),
    do: cast(checks_interval, attrs, [:target_id, :target_type, :interval])
end
