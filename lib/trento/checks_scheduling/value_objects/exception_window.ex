# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling.ValueObjects.ExceptionWindow do
  @moduledoc """
  The exception window of a host or cluster: a time window in which its
  checks are not executed periodically. One-time without a frequency,
  otherwise repeating in the local time of its timezone, see
  `Trento.Scheduling.Recurrence`.
  """

  @required_fields [:starts_at, :timezone, :duration_minutes]

  use Trento.Support.Type

  alias Trento.Scheduling.Recurrence

  deftype do
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    field :duration_minutes, :integer
    field :frequency, Ecto.Enum, values: Recurrence.frequencies()
    field :interval, :integer
    field :weekdays, {:array, :integer}
  end

  def changeset(window, attrs) do
    window
    |> cast(attrs, [:starts_at, :timezone, :duration_minutes, :frequency, :interval, :weekdays])
    |> validate_required(@required_fields)
    |> validate_number(:duration_minutes, greater_than: 0)
    |> validate_number(:interval, greater_than: 0)
    |> validate_subset(:weekdays, Enum.to_list(1..7))
    |> validate_change(:timezone, fn :timezone, timezone ->
      if Tzdata.zone_exists?(timezone), do: [], else: [timezone: "is not a valid timezone"]
    end)
  end

  @doc """
  The attributes of a window given as the API describes it, with its
  recurrence apart.
  """
  @spec attrs(map()) :: map()
  def attrs(window) do
    recurrence = Map.get(window, :recurrence) || %{}
    periodic? = recurrence != %{}

    %{
      starts_at: Map.get(window, :starts_at),
      timezone: Map.get(window, :timezone),
      duration_minutes: Map.get(window, :duration_minutes),
      frequency: Map.get(recurrence, :frequency),
      interval: Map.get(recurrence, :interval, if(periodic?, do: 1)),
      weekdays: Map.get(recurrence, :weekdays, if(periodic?, do: []))
    }
  end

  @doc """
  The window as the API describes it.
  """
  @spec to_map(t() | nil) :: map() | nil
  def to_map(nil), do: nil

  def to_map(%__MODULE__{} = window) do
    %{
      starts_at: window.starts_at,
      timezone: window.timezone,
      duration_minutes: window.duration_minutes,
      recurrence:
        window.frequency &&
          %{
            frequency: Atom.to_string(window.frequency),
            interval: window.interval,
            weekdays: window.weekdays
          }
    }
  end

  @doc """
  Tells whether a one-time window is over at `now`. A periodic window never is.
  """
  @spec ended?(t(), DateTime.t()) :: boolean()
  def ended?(%__MODULE__{frequency: nil} = window, now),
    do:
      DateTime.compare(DateTime.add(window.starts_at, window.duration_minutes, :minute), now) ==
        :lt

  def ended?(%__MODULE__{}, _now), do: false

  @doc """
  The end of the occurrence of the window covering `at`, nil outside the window.
  """
  @spec window_end(t() | nil, DateTime.t()) :: DateTime.t() | nil
  def window_end(nil, _at), do: nil

  def window_end(%__MODULE__{duration_minutes: duration} = window, at) do
    from = DateTime.add(at, -duration * 60 - 1, :second)

    with %DateTime{} = start <- Recurrence.next_occurrence(to_rule(window), from),
         true <- DateTime.compare(start, at) != :gt,
         ends_at = DateTime.add(start, duration, :minute),
         :gt <- DateTime.compare(ends_at, at) do
      ends_at
    else
      _ -> nil
    end
  end

  defp to_rule(%__MODULE__{} = window) do
    %{
      starts_at: window.starts_at,
      timezone: window.timezone,
      frequency: window.frequency,
      interval: window.interval || 1,
      weekdays: window.weekdays || []
    }
  end
end
