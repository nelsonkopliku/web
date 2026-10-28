# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows do
  @moduledoc """
  Maintenance windows (TRNT-4774): one-time or periodic time slots in which
  Trento does not execute checks, or does not run operations, on a target
  and on the targets it covers.

  Event sourced: every change is a command to a
  `Trento.MaintenanceWindows.MaintenanceWindow` aggregate, and the reads come
  from the maintenance_windows read model. A change waits until the read
  model shows it, so that the answer and the next read show the change. When
  the read model takes too long, the change is saved anyway: it is logged,
  and `{:error, :consistency_timeout}` tells that the read model does not
  show it yet.
  """

  import Ecto.Query, only: [from: 2]

  alias Trento.Clusters.Projections.ClusterReadModel
  alias Trento.Databases.Projections.DatabaseReadModel
  alias Trento.Hosts.Projections.HostReadModel

  alias Trento.MaintenanceWindows.Commands.{
    ChangeMaintenanceWindow,
    DeleteMaintenanceWindow,
    ScheduleMaintenanceWindow
  }

  alias Trento.MaintenanceWindows.Projections.{
    MaintenanceWindowProjector,
    MaintenanceWindowReadModel
  }

  alias Trento.MaintenanceWindows.{Coverage, WindowActivity}
  alias Trento.Repo
  alias Trento.SapSystems.Projections.SapSystemReadModel
  alias Trento.Scheduling.Recurrence
  alias Trento.Support.{CommandedUtils, DateService}

  require Logger

  @doc """
  Sets a maintenance window on a registered target.
  """
  @spec create_window(map(), String.t(), module()) ::
          {:ok, MaintenanceWindowReadModel.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
          | {:error, :consistency_timeout}
          | {:error, any()}
  def create_window(attrs, actor, date_service \\ DateService) do
    changeset = schedule_changeset(attrs, UUID.uuid4(), date_service.utc_now())

    with {:ok, command} <- Ecto.Changeset.apply_action(changeset, :insert),
         :ok <- registered(command.target_type, command.target_id) do
      command
      |> dispatch(metadata: %{"created_by" => actor})
      |> saved(changeset, command.window_id, fn window ->
        WindowActivity.record(
          :maintenance_window_scheduled,
          window || provisional(command),
          actor
        )
      end)
    end
  end

  @doc """
  Replaces the timing and the forbidden actions of a window. The change
  applies at once, also to an ongoing window, which can keep its start.
  """
  @spec update_window(String.t(), map(), String.t(), module()) ::
          {:ok, MaintenanceWindowReadModel.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
          | {:error, :consistency_timeout}
          | {:error, any()}
  def update_window(window_id, attrs, actor, date_service \\ DateService) do
    changeset =
      ChangeMaintenanceWindow.changeset(
        %ChangeMaintenanceWindow{},
        Map.merge(attrs, %{window_id: window_id, requested_at: date_service.utc_now()})
      )

    with {:ok, current} <- get_window(window_id),
         {:ok, command} <- Ecto.Changeset.apply_action(changeset, :update) do
      command
      |> dispatch([])
      |> saved(changeset, window_id, fn window ->
        WindowActivity.record(
          :maintenance_window_changed,
          window || provisional(command, current),
          actor
        )
      end)
    end
  end

  @doc """
  Deletes a window. A window deleted meanwhile is not found.
  """
  @spec delete_window(String.t(), String.t()) ::
          :ok | {:error, :not_found} | {:error, :consistency_timeout} | {:error, any()}
  def delete_window(window_id, actor) do
    with {:ok, window} <- get_window(window_id) do
      %{window_id: window_id}
      |> DeleteMaintenanceWindow.new!()
      |> dispatch([])
      |> deleted(window, actor, %{})
    end
  end

  @doc """
  Deletes the windows of a target that is removed. The entries are logged by
  the system and correlated to the clean up that removed the target: `cause`
  holds its correlation and causation ids. A window deleted meanwhile is
  skipped; the other windows are deleted anyway, and the first error is
  returned, so that the clean up can retry.
  """
  @spec delete_target_windows(String.t(), keyword()) :: :ok | {:error, any()}
  def delete_target_windows(target_id, cause) do
    extra = Map.new(Keyword.take(cause, [:correlation_id]))

    from(w in MaintenanceWindowReadModel, where: w.target_id == ^target_id)
    |> Repo.all()
    |> Enum.map(fn %MaintenanceWindowReadModel{id: window_id} = window ->
      %{window_id: window_id}
      |> DeleteMaintenanceWindow.new!()
      |> CommandedUtils.dispatch([consistency: [MaintenanceWindowProjector]] ++ cause)
      |> deleted(window, "system", extra)
    end)
    |> Enum.find(:ok, &match?({:error, reason} when reason != :consistency_timeout, &1))
  end

  @type covering_window :: %{
          window: MaintenanceWindowReadModel.t(),
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
  @spec own_window(MaintenanceWindowReadModel.t(), module()) :: covering_window()
  def own_window(%MaintenanceWindowReadModel{} = window, date_service \\ DateService) do
    target = {window.target_type, window.target_id}
    covering(window, target, target_names([target]), date_service.utc_now())
  end

  @spec get_window(String.t()) :: {:ok, MaintenanceWindowReadModel.t()} | {:error, :not_found}
  def get_window(window_id) do
    case Repo.get(MaintenanceWindowReadModel, window_id) do
      nil -> {:error, :not_found}
      window -> {:ok, window}
    end
  end

  @doc """
  The occurrence of a window ongoing at `at`, and the next one after it.
  """
  @spec occurrences(MaintenanceWindowReadModel.t(), DateTime.t()) ::
          {occurrence() | nil, occurrence() | nil}
  def occurrences(%MaintenanceWindowReadModel{duration_minutes: duration} = window, at) do
    recurrence = MaintenanceWindowReadModel.to_recurrence(window)

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

    from(w in MaintenanceWindowReadModel, where: w.target_id in ^ids)
    |> Repo.all()
    |> Enum.filter(&({&1.target_type, &1.target_id} in owners))
  end

  defp covering(%MaintenanceWindowReadModel{} = window, target, names, now) do
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
  same bulk_id.

  Every target is checked before any window is saved, so an unknown target
  or an invalid window saves nothing. The windows are separate aggregates:
  when one cannot be saved, the ones saved before are deleted, so the
  request saves all of them or none.
  """
  @spec create_bulk_windows(map(), String.t(), module()) ::
          {:ok, String.t(), [MaintenanceWindowReadModel.t()]}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
          | {:error, :consistency_timeout}
          | {:error, any()}
  def create_bulk_windows(%{target_ids: target_ids} = attrs, actor, date_service \\ DateService) do
    bulk_id = UUID.uuid4()
    requested_at = date_service.utc_now()
    common = attrs |> Map.delete(:target_ids) |> Map.put(:bulk_id, bulk_id)

    changesets =
      Enum.map(target_ids, fn target_id ->
        schedule_changeset(Map.put(common, :target_id, target_id), UUID.uuid4(), requested_at)
      end)

    with {:ok, commands} <- validate_bulk(changesets),
         {:ok, dispatched} <- dispatch_bulk(Enum.zip(changesets, commands), actor) do
      windows =
        Enum.map(dispatched, fn {command, _} ->
          window = Repo.get(MaintenanceWindowReadModel, command.window_id)

          WindowActivity.record(
            :maintenance_window_scheduled,
            window || provisional(command),
            actor
          )

          window
        end)

      if Enum.any?(dispatched, &match?({_, {:error, :consistency_timeout}}, &1)),
        do: {:error, :consistency_timeout},
        else: {:ok, bulk_id, windows}
    end
  end

  defp validate_bulk(changesets) do
    changesets
    |> Enum.reduce_while({:ok, []}, fn changeset, {:ok, commands} ->
      with {:ok, command} <- Ecto.Changeset.apply_action(changeset, :insert),
           :ok <- registered(command.target_type, command.target_id) do
        {:cont, {:ok, [command | commands]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, commands} -> {:ok, Enum.reverse(commands)}
      error -> error
    end
  end

  # The windows share their timing: when it does not hold, the first one is
  # refused and nothing is saved.
  defp dispatch_bulk(prepared, actor) do
    prepared
    |> Enum.reduce_while({:ok, []}, fn {changeset, command}, {:ok, dispatched} ->
      case dispatch(command, metadata: %{"created_by" => actor}) do
        result when result in [:ok, {:error, :consistency_timeout}] ->
          {:cont, {:ok, [{command, result} | dispatched]}}

        error ->
          {:halt, {:error, error, changeset, dispatched}}
      end
    end)
    |> case do
      {:ok, dispatched} ->
        {:ok, Enum.reverse(dispatched)}

      {:error, error, changeset, dispatched} ->
        Enum.each(dispatched, fn {command, _} -> compensate(command) end)
        saved(error, changeset, nil, fn _ -> :ok end)
    end
  end

  defp compensate(%ScheduleMaintenanceWindow{window_id: window_id}) do
    Logger.warning("Maintenance window #{window_id} deleted: its bulk request failed")

    %{window_id: window_id}
    |> DeleteMaintenanceWindow.new!()
    |> dispatch([])
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

  defp schedule_changeset(attrs, window_id, requested_at) do
    ScheduleMaintenanceWindow.changeset(
      %ScheduleMaintenanceWindow{},
      Map.merge(attrs, %{window_id: window_id, requested_at: requested_at})
    )
  end

  # Waits for the read model of the windows, see the moduledoc.
  defp dispatch(command, opts) do
    CommandedUtils.correlated_dispatch(
      command,
      [consistency: [MaintenanceWindowProjector]] ++ opts
    )
  end

  # A command that went through is logged, even when the read model is late.
  # The aggregate refuses a window that starts in the past or is over: the
  # error is told on the start.
  defp saved(:ok, _changeset, window_id, log) do
    window = Repo.get!(MaintenanceWindowReadModel, window_id)
    log.(window)
    {:ok, window}
  end

  defp saved({:error, :consistency_timeout}, _changeset, window_id, log) do
    Logger.warning("Maintenance window #{window_id} saved, its read model is not up to date")
    log.(nil)
    {:error, :consistency_timeout}
  end

  defp saved({:error, :maintenance_window_start_in_the_past}, changeset, _, _),
    do: {:error, Ecto.Changeset.add_error(changeset, :starts_at, "is in the past")}

  defp saved({:error, :maintenance_window_over}, changeset, _, _),
    do:
      {:error,
       Ecto.Changeset.add_error(changeset, :starts_at, "leaves no occurrence that is not over")}

  defp saved({:error, :maintenance_window_not_found}, _, _, _), do: {:error, :not_found}

  defp saved({:error, _} = error, _, _, _), do: error

  defp deleted(result, window, actor, extra)
       when result in [:ok, {:error, :consistency_timeout}] do
    WindowActivity.record(:maintenance_window_deleted, window, actor, extra)
    result
  end

  defp deleted({:error, :maintenance_window_not_found}, _, "system", _), do: :ok
  defp deleted({:error, :maintenance_window_not_found}, _, _, _), do: {:error, :not_found}

  defp deleted({:error, reason} = error, %{id: window_id}, _, _) do
    Logger.error("Maintenance window #{window_id} could not be deleted: #{inspect(reason)}")
    error
  end

  # The window as the read model will show it, to log a change that the read
  # model does not show yet.
  defp provisional(%ScheduleMaintenanceWindow{} = command) do
    provisional(command, %MaintenanceWindowReadModel{
      id: command.window_id,
      target_type: command.target_type,
      target_id: command.target_id,
      bulk_id: command.bulk_id
    })
  end

  defp provisional(command, %MaintenanceWindowReadModel{} = current) do
    recurrence = command.recurrence

    %MaintenanceWindowReadModel{
      current
      | starts_at: command.starts_at,
        timezone: command.timezone,
        duration_minutes: command.duration_minutes,
        frequency: recurrence && Atom.to_string(recurrence.frequency),
        interval: (recurrence && recurrence.interval) || 1,
        weekdays: (recurrence && recurrence.weekdays) || [],
        ends_on: recurrence && recurrence.ends_on,
        forbid_checks_execution: :checks_execution in command.forbids,
        forbid_operations: :operations in command.forbids
    }
  end
end
