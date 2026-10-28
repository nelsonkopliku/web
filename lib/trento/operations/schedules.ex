# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Schedules do
  @moduledoc """
  Operation schedules, event sourced: every change is a command to a
  `Trento.Operations.Schedule` aggregate, and the reads come from the
  operation_schedules read model.

  A change waits until the read model shows it, so that the answer and the
  next read show the change. When the read model takes too long, the change
  is saved anyway: it is logged, and `{:error, :consistency_timeout}` tells
  that the read model does not show it yet.
  """

  import Ecto.Query, only: [from: 2, where: 3]

  alias Trento.Operations.Commands.{ChangeOperationSchedule, ScheduleOperation}
  alias Trento.Operations.Projections.{OperationScheduleProjector, OperationScheduleReadModel}
  alias Trento.Operations.{Requests, ScheduleActivity}
  alias Trento.Operations.ValueObjects.{OperationParams, Recurrence}
  alias Trento.Repo
  alias Trento.Support.{CommandedUtils, DateService}

  require Logger

  @type warnings :: [map()]

  @doc """
  Schedules an operation. The schedule is saved even when the operation
  policies fail now: they are returned as warnings and run again when the
  schedule is due.
  """
  @spec create_schedule(map(), String.t(), module()) ::
          {:ok, OperationScheduleReadModel.t(), warnings()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
          | {:error, :consistency_timeout}
          | {:error, any()}
  def create_schedule(attrs, actor, date_service \\ DateService) do
    changeset = schedule_changeset(attrs, UUID.uuid4(), date_service.utc_now())

    with {:ok, command} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, warnings} <- policy_warnings(command, command.params) do
      command
      |> dispatch(metadata: %{"created_by" => actor})
      |> saved(changeset, command.schedule_id, fn schedule ->
        ScheduleActivity.record(:operation_scheduled, schedule || provisional(command), actor)
      end)
      |> with_warnings(warnings)
    end
  end

  @doc """
  Replaces the params and the timing of a schedule. The occurrence count
  restarts. Failing operation policies come back as warnings.
  """
  @spec update_schedule(String.t(), map(), String.t(), module()) ::
          {:ok, OperationScheduleReadModel.t(), warnings()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
          | {:error, :consistency_timeout}
          | {:error, any()}
  def update_schedule(schedule_id, attrs, actor, date_service \\ DateService) do
    with {:ok, current} <- get_schedule(schedule_id),
         changeset = change_changeset(attrs, schedule_id, date_service.utc_now()),
         {:ok, command} <- Ecto.Changeset.apply_action(changeset, :update),
         {:ok, warnings} <- policy_warnings(current, command.params) do
      command
      |> dispatch([])
      |> saved(changeset, schedule_id, fn schedule ->
        ScheduleActivity.record(
          :operation_schedule_changed,
          schedule || provisional(command, current),
          actor
        )
      end)
      |> with_warnings(warnings)
    end
  end

  @doc """
  Lists the schedules of one or more targets, the next one first. With the
  `operation` option, only the schedules of that operation.
  """
  @spec list_schedules(String.t() | [String.t()], keyword()) :: [OperationScheduleReadModel.t()]
  def list_schedules(target_ids, opts \\ [])

  def list_schedules(target_id, opts) when is_binary(target_id),
    do: list_schedules([target_id], opts)

  def list_schedules(target_ids, opts) do
    query =
      from s in OperationScheduleReadModel,
        where: s.target_id in ^target_ids,
        order_by: [asc: s.next_run_at, asc: s.inserted_at]

    query =
      case Keyword.get(opts, :operation) do
        nil -> query
        operation -> where(query, [s], s.operation == ^operation)
      end

    Repo.all(query)
  end

  @spec get_schedule(String.t()) :: {:ok, OperationScheduleReadModel.t()} | {:error, :not_found}
  def get_schedule(schedule_id) do
    case Repo.get(OperationScheduleReadModel, schedule_id) do
      nil -> {:error, :not_found}
      schedule -> {:ok, schedule}
    end
  end

  defp schedule_changeset(attrs, schedule_id, requested_at) do
    ScheduleOperation.changeset(
      %ScheduleOperation{},
      attrs
      |> Map.merge(%{schedule_id: schedule_id, requested_at: requested_at})
      |> Map.update(:params, %{}, &(&1 || %{}))
    )
  end

  defp change_changeset(attrs, schedule_id, requested_at) do
    ChangeOperationSchedule.changeset(
      %ChangeOperationSchedule{},
      attrs
      |> Map.merge(%{schedule_id: schedule_id, requested_at: requested_at})
      |> Map.update(:params, %{}, &(&1 || %{}))
    )
  end

  defp policy_warnings(%{target_type: target_type, operation: operation} = schedule, params) do
    {:ok, target_type, operation} = Requests.parse(target_type, operation)

    case Requests.authorize(
           target_type,
           schedule.target_id,
           operation,
           OperationParams.to_map(params)
         ) do
      :ok -> {:ok, []}
      {:error, :forbidden, errors} -> {:ok, errors}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  # Waits for the read model of the schedules, see the moduledoc.
  defp dispatch(command, opts) do
    CommandedUtils.correlated_dispatch(
      command,
      [consistency: [OperationScheduleProjector]] ++ opts
    )
  end

  # A command that went through is logged, even when the read model is late.
  # The aggregate refuses a timing that leaves no occurrence: the error is
  # told on the field that causes it.
  defp saved(:ok, _changeset, schedule_id, log) do
    schedule = Repo.get!(OperationScheduleReadModel, schedule_id)
    log.(schedule)
    {:ok, schedule}
  end

  defp saved({:error, :consistency_timeout}, _changeset, schedule_id, log) do
    Logger.warning("Operation schedule #{schedule_id} saved, its read model is not up to date")
    log.(nil)
    {:error, :consistency_timeout}
  end

  defp saved({:error, :operation_schedule_start_in_the_past}, changeset, _, _),
    do: {:error, Ecto.Changeset.add_error(changeset, :starts_at, "is in the past")}

  defp saved({:error, :operation_schedule_without_occurrences}, changeset, _, _) do
    {:error,
     Ecto.Changeset.update_change(
       changeset,
       :recurrence,
       &Ecto.Changeset.add_error(&1, :ends_on, "leaves no occurrence")
     )}
  end

  defp saved({:error, :operation_schedule_not_found}, _, _, _), do: {:error, :not_found}

  defp saved({:error, _} = error, _, _, _), do: error

  defp with_warnings({:ok, schedule}, warnings), do: {:ok, schedule, warnings}
  defp with_warnings(error, _), do: error

  # The schedule as the read model will show it, to log a change that the
  # read model does not show yet. The next occurrence is not known.
  defp provisional(%ScheduleOperation{} = command) do
    provisional(command, %OperationScheduleReadModel{
      id: command.schedule_id,
      target_type: command.target_type,
      target_id: command.target_id,
      operation: command.operation,
      bulk_id: command.bulk_id
    })
  end

  defp provisional(command, %OperationScheduleReadModel{} = current) do
    struct(
      %OperationScheduleReadModel{
        current
        | params: OperationParams.to_map(command.params),
          starts_at: command.starts_at,
          timezone: command.timezone,
          next_run_at: nil
      },
      Recurrence.to_map(command.recurrence) || %{frequency: nil}
    )
  end
end
