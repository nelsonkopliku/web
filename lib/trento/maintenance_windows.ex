# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows do
  @moduledoc """
  Maintenance windows (TRNT-4774): one-time or periodic time slots in which
  Trento does not execute checks, or does not run operations, on a target
  and on the targets it covers.
  """

  import Ecto.Query, only: [from: 2]

  alias Trento.Clusters.Projections.ClusterReadModel
  alias Trento.Databases.Projections.DatabaseReadModel
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.MaintenanceWindows.{Coverage, MaintenanceWindow, WindowActivity}
  alias Trento.Repo
  alias Trento.Scheduling.Recurrence
  alias Trento.SapSystems.Projections.SapSystemReadModel
  alias Trento.Support.DateService

  @doc """
  Sets a maintenance window on a registered target.
  """
  @spec create_window(map(), String.t(), module()) ::
          {:ok, MaintenanceWindow.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def create_window(attrs, actor, date_service \\ DateService) do
    changeset =
      MaintenanceWindow.changeset(
        %MaintenanceWindow{},
        Map.put(attrs, :created_by, actor),
        date_service.utc_now()
      )

    with {:ok, window} <- Ecto.Changeset.apply_action(changeset, :insert),
         :ok <- registered(window.target_type, window.target_id),
         {:ok, window} <- Repo.insert(changeset) do
      WindowActivity.record(:maintenance_window_scheduled, window, actor)
      {:ok, window}
    end
  end

  @type covering_window :: %{
          window: MaintenanceWindow.t(),
          target_name: String.t() | nil,
          inherited: boolean(),
          active: boolean(),
          current_occurrence: occurrence() | nil,
          next_occurrence: occurrence() | nil
        }

  @type occurrence :: %{starts_at: DateTime.t(), ends_at: DateTime.t()}

  @doc """
  The windows that cover a target, set on it or inherited from the targets
  that cover it, with an occurrence that is ongoing or ahead. The active ones
  come first, then the next to start.
  """
  @spec list_covering_windows(String.t(), String.t(), module()) :: [covering_window()]
  def list_covering_windows(target_type, target_id, date_service \\ DateService) do
    now = date_service.utc_now()
    owners = Coverage.owners(target_type, target_id)
    names = target_names(owners)

    owners
    |> windows_of()
    |> Enum.map(&covering(&1, {target_type, target_id}, names, now))
    |> Enum.filter(&(&1.active or &1.next_occurrence != nil))
    |> Enum.sort_by(&{not &1.active, sort_start(&1)})
  end

  @spec get_window(String.t()) :: {:ok, MaintenanceWindow.t()} | {:error, :not_found}
  def get_window(window_id) do
    case Repo.get(MaintenanceWindow, window_id) do
      nil -> {:error, :not_found}
      window -> {:ok, window}
    end
  end

  @doc """
  The occurrence of a window ongoing at `at`, and the next one after it.
  """
  @spec occurrences(MaintenanceWindow.t(), DateTime.t()) ::
          {occurrence() | nil, occurrence() | nil}
  def occurrences(%MaintenanceWindow{duration_minutes: duration} = window, at) do
    recurrence = MaintenanceWindow.to_recurrence(window)

    case Recurrence.next_occurrence(recurrence, DateTime.add(at, -duration, :minute)) do
      nil ->
        {nil, nil}

      start ->
        if DateTime.compare(start, at) == :gt do
          {nil, occurrence(start, duration)}
        else
          {occurrence(start, duration),
           recurrence |> Recurrence.next_occurrence(start) |> occurrence(duration)}
        end
    end
  end

  defp occurrence(nil, _), do: nil

  defp occurrence(start, duration),
    do: %{starts_at: start, ends_at: DateTime.add(start, duration, :minute)}

  defp windows_of(owners) do
    ids = Enum.map(owners, &elem(&1, 1))

    from(w in MaintenanceWindow, where: w.target_id in ^ids)
    |> Repo.all()
    |> Enum.filter(&({&1.target_type, &1.target_id} in owners))
  end

  defp covering(%MaintenanceWindow{} = window, target, names, now) do
    {current, next} = occurrences(window, now)

    %{
      window: window,
      target_name: Map.get(names, {window.target_type, window.target_id}),
      inherited: {window.target_type, window.target_id} != target,
      active: current != nil,
      current_occurrence: current,
      next_occurrence: next
    }
  end

  defp sort_start(%{current_occurrence: %{starts_at: starts_at}}),
    do: DateTime.to_unix(starts_at, :microsecond)

  defp sort_start(%{next_occurrence: %{starts_at: starts_at}}),
    do: DateTime.to_unix(starts_at, :microsecond)

  defp target_names(owners) do
    owners
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {target_type, ids} -> names_of(target_type, ids) end)
    |> Map.new()
  end

  defp names_of("host", ids),
    do: named(from(h in HostReadModel, where: h.id in ^ids, select: {h.id, h.hostname}), "host")

  defp names_of("cluster", ids),
    do: named(from(c in ClusterReadModel, where: c.id in ^ids, select: {c.id, c.name}), "cluster")

  defp names_of("database", ids),
    do:
      named(from(d in DatabaseReadModel, where: d.id in ^ids, select: {d.id, d.sid}), "database")

  defp names_of("sap_system", ids),
    do:
      named(
        from(s in SapSystemReadModel, where: s.id in ^ids, select: {s.id, s.sid}),
        "sap_system"
      )

  defp named(query, target_type),
    do: query |> Repo.all() |> Enum.map(fn {id, name} -> {{target_type, id}, name} end)

  @doc """
  Tells whether a target is registered: a window can only be set on one.
  """
  @spec registered(String.t(), String.t()) :: :ok | {:error, :not_found}
  def registered(target_type, target_id) do
    query =
      from t in read_model(target_type),
        where: t.id == ^target_id and is_nil(t.deregistered_at),
        select: true

    if Repo.exists?(query), do: :ok, else: {:error, :not_found}
  end

  defp read_model("host"), do: HostReadModel
  defp read_model("cluster"), do: ClusterReadModel
  defp read_model("database"), do: DatabaseReadModel
  defp read_model("sap_system"), do: SapSystemReadModel
end
