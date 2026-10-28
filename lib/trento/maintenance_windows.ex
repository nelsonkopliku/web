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

  @doc """
  Replaces the timing and the forbidden actions of a window. The change
  applies at once, also to an ongoing window, which can keep its start.
  """
  @spec update_window(String.t(), map(), String.t(), module()) ::
          {:ok, MaintenanceWindow.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_window(window_id, attrs, actor, date_service \\ DateService) do
    with {:ok, current} <- get_window(window_id),
         {:ok, window} <-
           current
           |> MaintenanceWindow.update_changeset(attrs, date_service.utc_now())
           |> Repo.update(stale_error_field: :id) do
      WindowActivity.record(:maintenance_window_changed, window, actor)
      {:ok, window}
    end
  end

  @doc """
  Deletes a window. A window deleted meanwhile is not found.
  """
  @spec delete_window(String.t(), String.t()) :: :ok | {:error, :not_found}
  def delete_window(window_id, actor) do
    with {:ok, window} <- get_window(window_id),
         {:ok, window} <- delete(window) do
      WindowActivity.record(:maintenance_window_deleted, window, actor)
    end
  end

  @doc """
  Deletes the windows of a target that is removed. The entries are logged by
  the system and correlated to the clean up that removed the target.
  """
  @spec delete_target_windows(String.t(), String.t() | nil) :: :ok
  def delete_target_windows(target_id, correlation_id) do
    extra = if correlation_id, do: %{correlation_id: correlation_id}, else: %{}

    from(w in MaintenanceWindow, where: w.target_id == ^target_id)
    |> Repo.all()
    |> Enum.each(fn window ->
      with {:ok, window} <- delete(window) do
        WindowActivity.record(:maintenance_window_deleted, window, "system", extra)
      end
    end)
  end

  defp delete(%MaintenanceWindow{} = window) do
    case Repo.delete(window, stale_error_field: :id) do
      {:ok, window} -> {:ok, window}
      {:error, _} -> {:error, :not_found}
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

  @doc """
  A window seen from the target it is set on.
  """
  @spec own_window(MaintenanceWindow.t(), module()) :: covering_window()
  def own_window(%MaintenanceWindow{} = window, date_service \\ DateService) do
    target = {window.target_type, window.target_id}
    covering(window, target, target_names([target]), date_service.utc_now())
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
  Sets the same window on several registered targets of one type, with the
  same bulk_id. All the windows are saved, or none.
  """
  @spec create_bulk_windows(map(), String.t(), module()) ::
          {:ok, String.t(), [MaintenanceWindow.t()]}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def create_bulk_windows(%{target_ids: target_ids} = attrs, actor, date_service \\ DateService) do
    bulk_id = UUID.uuid4()
    now = date_service.utc_now()

    common =
      attrs
      |> Map.delete(:target_ids)
      |> Map.merge(%{bulk_id: bulk_id, created_by: actor})

    changesets =
      Enum.map(target_ids, fn target_id ->
        MaintenanceWindow.changeset(
          %MaintenanceWindow{},
          Map.put(common, :target_id, target_id),
          now
        )
      end)

    with :ok <- validate_bulk(changesets),
         {:ok, windows} <- insert_bulk(changesets) do
      Enum.each(windows, &WindowActivity.record(:maintenance_window_scheduled, &1, actor))
      {:ok, bulk_id, windows}
    end
  end

  defp validate_bulk(changesets) do
    Enum.reduce_while(changesets, :ok, fn changeset, :ok ->
      with {:ok, window} <- Ecto.Changeset.apply_action(changeset, :insert),
           :ok <- registered(window.target_type, window.target_id) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp insert_bulk(changesets) do
    changesets
    |> Enum.with_index()
    |> Enum.reduce(Ecto.Multi.new(), fn {changeset, index}, multi ->
      Ecto.Multi.insert(multi, index, changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, changes} -> {:ok, Enum.map(0..(length(changesets) - 1), &changes[&1])}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  When the windows that cover a target stop forbidding an action, from `at`
  on: the end of the last window of a chain of overlapping ones. Nil when no
  window forbids the action at `at`.
  """
  @spec forbidden_until(String.t(), String.t(), atom(), DateTime.t()) :: DateTime.t() | nil
  def forbidden_until(target_type, target_id, action, at) do
    windows =
      target_type
      |> Coverage.owners(target_id)
      |> windows_of()
      |> Enum.filter(&MaintenanceWindow.forbids?(&1, action))

    case chain_end(windows, at, 0) do
      ^at -> nil
      ends_at -> ends_at
    end
  end

  @doc """
  The ongoing window that forbids an action on a target, if any, with its end
  and the name of the target it is set on.
  """
  @spec forbidding_window(String.t(), String.t(), atom(), module()) ::
          {:ok, MaintenanceWindow.t(), String.t() | nil, DateTime.t()} | :none
  def forbidding_window(target_type, target_id, action, date_service \\ DateService) do
    now = date_service.utc_now()
    owners = Coverage.owners(target_type, target_id)

    owners
    |> windows_of()
    |> Enum.filter(&MaintenanceWindow.forbids?(&1, action))
    |> Enum.flat_map(fn window ->
      case occurrences(window, now) do
        {%{ends_at: ends_at}, _} -> [{window, ends_at}]
        _ -> []
      end
    end)
    |> Enum.max_by(fn {_, ends_at} -> DateTime.to_unix(ends_at, :microsecond) end, fn -> nil end)
    |> case do
      nil ->
        :none

      {window, _} ->
        names = target_names([{window.target_type, window.target_id}])

        {:ok, window, Map.get(names, {window.target_type, window.target_id}),
         forbidden_until(target_type, target_id, action, now)}
    end
  end

  @doc """
  The hosts and clusters whose checks executions an ongoing window forbids.
  """
  @spec forbidden_checks_targets(DateTime.t()) :: MapSet.t(Coverage.target())
  def forbidden_checks_targets(now) do
    from(w in MaintenanceWindow, where: w.forbid_checks_execution)
    |> Repo.all()
    |> Enum.filter(&match?({%{}, _}, occurrences(&1, now)))
    |> Enum.flat_map(&Coverage.covered(&1.target_type, &1.target_id))
    |> Enum.filter(fn {target_type, _} -> target_type in ["host", "cluster"] end)
    |> MapSet.new()
  end

  # Windows can overlap or follow each other: the action stays forbidden
  # until the last one of the chain ends.
  @max_chain 100

  defp chain_end(_windows, at, @max_chain), do: at

  defp chain_end(windows, at, depth) do
    windows
    |> Enum.flat_map(fn window ->
      case occurrences(window, at) do
        {%{ends_at: ends_at}, _} -> [ends_at]
        _ -> []
      end
    end)
    |> Enum.max(DateTime, fn -> nil end)
    |> case do
      nil -> at
      ends_at -> chain_end(windows, ends_at, depth + 1)
    end
  end

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
