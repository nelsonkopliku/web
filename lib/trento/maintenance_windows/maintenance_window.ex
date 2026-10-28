# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.MaintenanceWindow do
  @moduledoc """
  A maintenance window: a one-time or periodic time slot, set on a host,
  cluster, database or SAP system, which forbids checks executions,
  operations, or both on the targets it covers.

  The recurrence follows `Trento.Scheduling.Recurrence`, without a number of
  occurrences: a periodic window ends on a date, or never.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Trento.Scheduling.Recurrence

  require Trento.MaintenanceWindows.Enums.ForbiddenAction, as: ForbiddenAction
  require Trento.MaintenanceWindows.Enums.TargetType, as: TargetType

  @type t :: %__MODULE__{}

  @target_types Enum.map(TargetType.values(), &Atom.to_string/1)
  @forbidden_actions Enum.map(ForbiddenAction.values(), &Atom.to_string/1)
  @frequency_atoms Map.new(Recurrence.frequencies(), &{Atom.to_string(&1), &1})
  @max_duration_minutes 31 * 24 * 60

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "maintenance_windows" do
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    field :duration_minutes, :integer
    field :frequency, :string
    field :interval, :integer, default: 1
    field :weekdays, {:array, :integer}, default: []
    field :ends_on, :date
    field :forbid_checks_execution, :boolean, default: false
    field :forbid_operations, :boolean, default: false
    field :bulk_id, Ecto.UUID
    field :created_by, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Validates a new window on a target. It starts in the future.
  """
  @spec changeset(t(), map(), DateTime.t()) :: Ecto.Changeset.t()
  def changeset(window, attrs, now) do
    window
    |> cast(attrs, [:target_type, :target_id, :bulk_id, :created_by])
    |> validate_required([:target_type, :target_id])
    |> validate_inclusion(:target_type, @target_types)
    |> timing_changeset(attrs, now)
  end

  @doc """
  Replaces the timing and the forbidden actions of a window. The start can
  stay in the past, so that an ongoing window can change.
  """
  @spec update_changeset(t(), map(), DateTime.t()) :: Ecto.Changeset.t()
  def update_changeset(window, attrs, now), do: timing_changeset(window, attrs, now)

  @spec forbids(t()) :: [String.t()]
  def forbids(%__MODULE__{} = window) do
    Enum.filter(@forbidden_actions, &forbids?(window, String.to_existing_atom(&1)))
  end

  @spec forbids?(t(), atom()) :: boolean()
  def forbids?(%__MODULE__{forbid_checks_execution: forbids}, :checks_execution), do: forbids
  def forbids?(%__MODULE__{forbid_operations: forbids}, :operations), do: forbids

  @spec recurrence(t()) :: map() | nil
  def recurrence(%__MODULE__{frequency: nil}), do: nil

  def recurrence(%__MODULE__{} = window),
    do: Map.take(window, [:frequency, :interval, :weekdays, :ends_on])

  @doc """
  The window in the shape `Trento.Scheduling.Recurrence` expects.
  """
  @spec to_recurrence(t()) :: Recurrence.t()
  def to_recurrence(%__MODULE__{} = window) do
    %{
      starts_at: window.starts_at,
      timezone: window.timezone,
      frequency: Map.get(@frequency_atoms, window.frequency),
      interval: window.interval,
      weekdays: window.weekdays,
      ends_on: window.ends_on,
      max_occurrences: nil,
      occurrences: 0
    }
  end

  defp timing_changeset(changeset, attrs, now) do
    recurrence = Map.get(attrs, :recurrence) || %{}

    changeset
    |> cast(attrs, [:starts_at, :timezone, :duration_minutes])
    |> cast(normalize_recurrence(recurrence), [:frequency, :interval, :weekdays, :ends_on])
    |> cast_forbids(Map.get(attrs, :forbids))
    |> validate_required([:starts_at, :timezone, :duration_minutes, :interval])
    |> validate_number(:duration_minutes,
      greater_than: 0,
      less_than_or_equal_to: @max_duration_minutes
    )
    |> validate_change(:starts_at, fn :starts_at, starts_at ->
      if DateTime.compare(starts_at, now) == :lt, do: [starts_at: "is in the past"], else: []
    end)
    |> validate_change(:timezone, fn :timezone, timezone ->
      if Tzdata.zone_exists?(timezone), do: [], else: [timezone: "is not a valid timezone"]
    end)
    |> validate_inclusion(:frequency, Map.keys(@frequency_atoms))
    |> validate_number(:interval, greater_than: 0)
    |> validate_subset(:weekdays, Enum.to_list(1..7))
    |> validate_occurrences_count(recurrence)
    |> validate_forbids()
    |> validate_not_over(now)
  end

  defp normalize_recurrence(recurrence) do
    recurrence
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.put_new("frequency", nil)
    |> Map.put_new("interval", 1)
    |> Map.put_new("weekdays", [])
    |> Map.put_new("ends_on", nil)
  end

  defp cast_forbids(changeset, nil), do: changeset

  defp cast_forbids(changeset, forbids) do
    forbids = Enum.map(forbids, &to_string/1)

    changeset
    |> put_change(:forbid_checks_execution, "checks_execution" in forbids)
    |> put_change(:forbid_operations, "operations" in forbids)
  end

  defp validate_forbids(changeset) do
    if get_field(changeset, :forbid_checks_execution) or get_field(changeset, :forbid_operations),
      do: changeset,
      else: add_error(changeset, :forbids, "must forbid checks executions, operations or both")
  end

  defp validate_occurrences_count(changeset, recurrence) do
    if Map.get(recurrence, :max_occurrences) || Map.get(recurrence, "max_occurrences"),
      do: add_error(changeset, :max_occurrences, "is not supported for maintenance windows"),
      else: changeset
  end

  # A window must have an occurrence that is not over yet.
  defp validate_not_over(%Ecto.Changeset{valid?: false} = changeset, _now), do: changeset

  defp validate_not_over(changeset, now) do
    window = apply_changes(changeset)
    from = DateTime.add(now, -window.duration_minutes, :minute)

    case Recurrence.next_occurrence(
           to_recurrence(window),
           Enum.max([from, window.starts_at |> DateTime.add(-1, :microsecond)], DateTime)
         ) do
      nil -> add_error(changeset, :starts_at, "leaves no occurrence that is not over")
      _ -> changeset
    end
  end
end
