# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling.TargetSchedule do
  @moduledoc """
  Checks execution settings of a host or cluster: its own interval (nil for
  the global one) and its last periodic request.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Trento.ChecksScheduling.Interval

  @type t :: %__MODULE__{}

  @primary_key {:target_id, Ecto.UUID, autogenerate: false}
  schema "checks_target_schedules" do
    field :target_type, :string
    field :interval, :string
    field :last_requested_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Replaces the interval. A nil interval means the global one.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(schedule, %{interval: interval}) do
    schedule
    |> cast(%{interval: interval}, [:interval])
    |> validate_inclusion(:interval, Interval.values(), message: "is not an allowed interval")
  end
end
