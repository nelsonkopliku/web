# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ValueObjects.Recurrence do
  @moduledoc """
  How an operation schedule repeats, see `Trento.Scheduling.Recurrence`.

  A one-time schedule has no recurrence.
  """

  @required_fields [:frequency, :interval]

  use Trento.Support.Type

  alias Trento.Scheduling.Recurrence

  deftype do
    field :frequency, Ecto.Enum, values: Recurrence.frequencies()
    field :interval, :integer, default: 1
    field :weekdays, {:array, :integer}, default: []
    field :ends_on, :date
    field :max_occurrences, :integer
  end

  def changeset(recurrence, params) do
    recurrence
    |> cast(params, [:frequency, :interval, :weekdays, :ends_on, :max_occurrences])
    |> validate_required(@required_fields)
    |> validate_number(:interval, greater_than: 0)
    |> validate_number(:max_occurrences, greater_than: 0)
    |> validate_subset(:weekdays, Enum.to_list(1..7))
  end

  @doc """
  The occurrences of a schedule starting at `starts_at` in `timezone`, after
  `occurrences` of them, in the shape `Trento.Scheduling.Recurrence` expects.
  """
  @spec to_rule(t() | nil, DateTime.t(), String.t(), non_neg_integer()) :: Recurrence.t()
  def to_rule(nil, starts_at, timezone, _occurrences),
    do: %{starts_at: starts_at, timezone: timezone, frequency: nil, interval: 1}

  def to_rule(%__MODULE__{} = recurrence, starts_at, timezone, occurrences) do
    %{
      starts_at: starts_at,
      timezone: timezone,
      frequency: recurrence.frequency,
      interval: recurrence.interval,
      weekdays: recurrence.weekdays,
      ends_on: recurrence.ends_on,
      max_occurrences: recurrence.max_occurrences,
      occurrences: occurrences
    }
  end

  @spec to_map(t() | nil) :: map() | nil
  def to_map(nil), do: nil

  def to_map(%__MODULE__{} = recurrence),
    do: Map.take(recurrence, [:frequency, :interval, :weekdays, :ends_on, :max_occurrences])
end
