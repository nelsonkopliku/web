# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.ValueObjects.Recurrence do
  @moduledoc """
  How a maintenance window repeats, see `Trento.Scheduling.Recurrence`. A
  periodic window ends on a date, or never: it has no number of occurrences.
  A one-time window has no recurrence.
  """

  @required_fields [:frequency, :interval]

  use Trento.Support.Type

  alias Trento.Scheduling.Recurrence

  deftype do
    field :frequency, Ecto.Enum, values: Recurrence.frequencies()
    field :interval, :integer, default: 1
    field :weekdays, {:array, :integer}, default: []
    field :ends_on, :date
  end

  def changeset(recurrence, params) do
    recurrence
    |> cast(params, [:frequency, :interval, :weekdays, :ends_on])
    |> validate_required(@required_fields)
    |> validate_number(:interval, greater_than: 0)
    |> validate_subset(:weekdays, Enum.to_list(1..7))
  end

  @doc """
  The occurrences of a window starting at `starts_at` in `timezone`, in the
  shape `Trento.Scheduling.Recurrence` expects.
  """
  @spec to_rule(t() | nil, DateTime.t(), String.t()) :: Recurrence.t()
  def to_rule(nil, starts_at, timezone),
    do: %{starts_at: starts_at, timezone: timezone, frequency: nil, interval: 1}

  def to_rule(%__MODULE__{} = recurrence, starts_at, timezone) do
    %{
      starts_at: starts_at,
      timezone: timezone,
      frequency: recurrence.frequency,
      interval: recurrence.interval,
      weekdays: recurrence.weekdays,
      ends_on: recurrence.ends_on
    }
  end
end
