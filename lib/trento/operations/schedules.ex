# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Schedules do
  @moduledoc """
  Operation schedules stored in the database. A Quantum job runs the due ones,
  see `Trento.Operations.Scheduler`.
  """

  import Ecto.Query, only: [from: 2, where: 3]

  alias Ecto.Multi
  alias Trento.Operations.{OperationSchedule, Requests, ScheduleActivity}
  alias Trento.Repo
  alias Trento.Support.DateService

  @type warnings :: [map()]

  @doc """
  Schedules an operation. The schedule is saved even when the operation
  policies fail now: they are returned as warnings and run again when the
  schedule is due.
  """
  @spec create_schedule(map(), String.t(), module()) ::
          {:ok, OperationSchedule.t(), warnings()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def create_schedule(attrs, actor, date_service \\ DateService) do
    changeset =
      OperationSchedule.changeset(
        %OperationSchedule{},
        Map.put(attrs, :created_by, actor),
        date_service.utc_now()
      )

    with {:ok, schedule} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, warnings} <- policy_warnings(schedule),
         {:ok, schedule} <- Repo.insert(changeset) do
      ScheduleActivity.record(:operation_scheduled, schedule, actor)
      {:ok, schedule, warnings}
    end
  end

  @doc """
  Schedules the same operation on several targets of one type: one schedule
  per target, all with the same bulk id. Nothing is saved when a target is
  unknown or the schedule is not valid. Failing policies come back as
  warnings, per target.
  """
  @spec create_bulk_schedules(map(), String.t(), module()) ::
          {:ok, String.t(), [{OperationSchedule.t(), warnings()}]}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def create_bulk_schedules(%{target_ids: target_ids} = attrs, actor, date_service \\ DateService) do
    bulk_id = UUID.uuid4()
    now = date_service.utc_now()

    common =
      attrs
      |> Map.delete(:target_ids)
      |> Map.merge(%{bulk_id: bulk_id, created_by: actor})

    with {:ok, prepared} <- prepare_bulk(target_ids, common, now),
         {:ok, schedules} <- insert_bulk(prepared) do
      Enum.each(schedules, &ScheduleActivity.record(:operation_scheduled, &1, actor))
      {:ok, bulk_id, Enum.zip(schedules, Enum.map(prepared, &elem(&1, 1)))}
    end
  end

  @doc """
  Replaces the params and the timing of a schedule. The occurrence count
  restarts. Failing operation policies come back as warnings.
  """
  @spec update_schedule(String.t(), map(), String.t(), module()) ::
          {:ok, OperationSchedule.t(), warnings()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def update_schedule(schedule_id, attrs, actor, date_service \\ DateService) do
    with {:ok, current} <- get_schedule(schedule_id),
         changeset = OperationSchedule.update_changeset(current, attrs, date_service.utc_now()),
         {:ok, schedule} <- Ecto.Changeset.apply_action(changeset, :update),
         {:ok, warnings} <- policy_warnings(schedule),
         {:ok, schedule} <- Repo.update(changeset) do
      ScheduleActivity.record(:operation_schedule_changed, schedule, actor)
      {:ok, schedule, warnings}
    end
  end

  @doc """
  Cancels a schedule: it no longer runs. An operation already running is not affected.
  """
  @spec cancel_schedule(String.t(), String.t()) :: :ok | {:error, :not_found}
  def cancel_schedule(schedule_id, actor) do
    with {:ok, schedule} <- get_schedule(schedule_id),
         {:ok, schedule} <- delete(schedule) do
      ScheduleActivity.record(:operation_schedule_cancelled, schedule, actor)
    end
  end

  @doc """
  Cancels the schedules of a target that is removed. The entries are logged
  by the system and correlated to the clean up that removed the target.
  """
  @spec cancel_target_schedules(String.t(), String.t() | nil) :: :ok
  def cancel_target_schedules(target_id, correlation_id) do
    target_id
    |> list_schedules()
    |> cancel_removed(correlation_id)
  end

  @doc """
  Cancels the SAP instance schedules of an instance that is removed, or of
  every instance on a host that is removed: SAP instance schedules target the
  SAP system and name the instance in their params.
  """
  @spec cancel_instance_schedules(keyword(), String.t() | nil) :: :ok
  def cancel_instance_schedules(instance, correlation_id) do
    query =
      from s in OperationSchedule,
        where:
          s.target_type == "sap_system" and
            s.operation in ["sap_instance_start", "sap_instance_stop"] and
            fragment("?->>'host_id'", s.params) == ^Keyword.fetch!(instance, :host_id)

    query =
      case Keyword.fetch(instance, :sap_system_id) do
        {:ok, sap_system_id} ->
          where(
            query,
            [s],
            s.target_id == ^sap_system_id and
              fragment("?->>'instance_number'", s.params) ==
                ^Keyword.fetch!(instance, :instance_number)
          )

        :error ->
          query
      end

    query
    |> Repo.all()
    |> cancel_removed(correlation_id)
  end

  @doc """
  """
  @spec list_schedules(String.t() | [String.t()], keyword()) :: [OperationSchedule.t()]
  def list_schedules(target_ids, opts \\ [])

  def list_schedules(target_id, opts) when is_binary(target_id),
    do: list_schedules([target_id], opts)

  def list_schedules(target_ids, opts) do
    query =
      from s in OperationSchedule,
        where: s.target_id in ^target_ids,
        order_by: [asc: s.next_run_at, asc: s.inserted_at]

    query =
      case Keyword.get(opts, :operation) do
        nil -> query
        operation -> where(query, [s], s.operation == ^operation)
      end

    Repo.all(query)
  end

  @spec get_schedule(String.t()) :: {:ok, OperationSchedule.t()} | {:error, :not_found}
  def get_schedule(schedule_id) do
    case Repo.get(OperationSchedule, schedule_id) do
      nil -> {:error, :not_found}
      schedule -> {:ok, schedule}
    end
  end

  defp prepare_bulk(target_ids, common, now) do
    target_ids
    |> Enum.reduce_while({:ok, []}, fn target_id, {:ok, acc} ->
      changeset =
        OperationSchedule.changeset(
          %OperationSchedule{},
          Map.put(common, :target_id, target_id),
          now
        )

      with {:ok, schedule} <- Ecto.Changeset.apply_action(changeset, :insert),
           {:ok, warnings} <- policy_warnings(schedule) do
        {:cont, {:ok, [{changeset, warnings} | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      error -> error
    end
  end

  # All the schedules of a bulk request are saved, or none.
  defp insert_bulk(prepared) do
    prepared
    |> Enum.with_index()
    |> Enum.reduce(Multi.new(), fn {{changeset, _}, index}, multi ->
      Multi.insert(multi, index, changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, changes} -> {:ok, Enum.map(0..(length(prepared) - 1), &changes[&1])}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  defp cancel_removed(schedules, correlation_id) do
    extra = if correlation_id, do: %{correlation_id: correlation_id}, else: %{}

    Enum.each(schedules, fn schedule ->
      with {:ok, schedule} <- delete(schedule) do
        ScheduleActivity.record(:operation_schedule_cancelled, schedule, "system", extra)
      end
    end)
  end

  # A schedule cancelled meanwhile, by a user or by the clean up, is not found.
  defp delete(%OperationSchedule{} = schedule) do
    case Repo.delete(schedule, stale_error_field: :id) do
      {:ok, schedule} -> {:ok, schedule}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp policy_warnings(%OperationSchedule{} = schedule) do
    {:ok, target_type, operation} = Requests.parse(schedule.target_type, schedule.operation)

    case Requests.authorize(target_type, schedule.target_id, operation, schedule.params) do
      :ok -> {:ok, []}
      {:error, :forbidden, errors} -> {:ok, errors}
      {:error, :not_found} -> {:error, :not_found}
    end
  end
end
