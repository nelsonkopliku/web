# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Projections.OperationScheduleReadModel do
  @moduledoc """
  Operation schedule read model: one row per schedule that has an occurrence
  to come. `next_run_at` is the next occurrence, `occurrences` the number of
  occurrences handled since the schedule was created or changed.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Trento.Scheduling.Recurrence

  @type t :: %__MODULE__{}

  @derive {Jason.Encoder, except: [:__meta__, :__struct__]}
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "operation_schedules" do
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :operation, :string
    field :params, :map, default: %{}
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    field :frequency, Ecto.Enum, values: Recurrence.frequencies()
    field :interval, :integer, default: 1
    field :weekdays, {:array, :integer}, default: []
    field :ends_on, :date
    field :max_occurrences, :integer
    field :next_run_at, :utc_datetime_usec
    field :occurrences, :integer, default: 0
    field :bulk_id, Ecto.UUID
    field :created_by, :string

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t() | Ecto.Changeset.t(), map) :: Ecto.Changeset.t()
  def changeset(schedule, attrs) do
    cast(schedule, attrs, __MODULE__.__schema__(:fields) -- [:inserted_at, :updated_at])
  end

  @doc """
  How the schedule repeats, nil for a one-time schedule.
  """
  @spec recurrence(t()) :: map() | nil
  def recurrence(%__MODULE__{frequency: nil}), do: nil

  def recurrence(%__MODULE__{} = schedule),
    do: Map.take(schedule, [:frequency, :interval, :weekdays, :ends_on, :max_occurrences])
end
