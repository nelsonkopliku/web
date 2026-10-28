# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling.Projections.TargetChecksExceptionWindowReadModel do
  @moduledoc """
  The exception window of a host or cluster, projected from its events.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Trento.ChecksScheduling.ValueObjects.ExceptionWindow
  alias Trento.Scheduling.Recurrence

  @type t :: %__MODULE__{}

  @fields [
    :target_id,
    :target_type,
    :starts_at,
    :timezone,
    :duration_minutes,
    :frequency,
    :interval,
    :weekdays
  ]

  @derive {Jason.Encoder, except: [:__meta__, :__struct__]}
  @primary_key {:target_id, Ecto.UUID, autogenerate: false}
  schema "target_checks_exception_windows" do
    field :target_type, :string
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    field :duration_minutes, :integer
    field :frequency, Ecto.Enum, values: Recurrence.frequencies()
    field :interval, :integer
    field :weekdays, {:array, :integer}

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t() | Ecto.Changeset.t(), map) :: Ecto.Changeset.t()
  def changeset(window, attrs), do: cast(window, attrs, @fields)

  @spec to_exception_window(t() | nil) :: ExceptionWindow.t() | nil
  def to_exception_window(nil), do: nil

  def to_exception_window(%__MODULE__{} = window),
    do: struct(ExceptionWindow, Map.take(window, @fields -- [:target_id, :target_type]))
end
