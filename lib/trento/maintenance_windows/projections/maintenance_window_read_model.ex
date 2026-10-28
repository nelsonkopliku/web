# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Projections.MaintenanceWindowReadModel do
  @moduledoc """
  Maintenance window read model, projected from the events of the windows.

  The recurrence follows `Trento.Scheduling.Recurrence`, without a number of
  occurrences: a periodic window ends on a date, or never.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Trento.Scheduling.Recurrence

  require Trento.MaintenanceWindows.Enums.ForbiddenAction, as: ForbiddenAction

  @type t :: %__MODULE__{}

  @forbidden_actions Enum.map(ForbiddenAction.values(), &Atom.to_string/1)
  @frequency_atoms Map.new(Recurrence.frequencies(), &{Atom.to_string(&1), &1})

  @derive {Jason.Encoder, except: [:__meta__, :__struct__]}
  @primary_key {:id, :binary_id, autogenerate: false}
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

  @spec changeset(t() | Ecto.Changeset.t(), map) :: Ecto.Changeset.t()
  def changeset(window, attrs),
    do: cast(window, attrs, __MODULE__.__schema__(:fields) -- [:inserted_at, :updated_at])

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
end
