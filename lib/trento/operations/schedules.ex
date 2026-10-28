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

  alias Trento.Operations.Commands.ScheduleOperation
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
         {:ok, warnings} <- policy_warnings(command) do
      command
      |> dispatch(metadata: %{"created_by" => actor})
      |> saved(changeset, command.schedule_id, fn schedule ->
        ScheduleActivity.record(:operation_scheduled, schedule || provisional(command), actor)
      end)
      |> with_warnings(warnings)
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

  defp policy_warnings(%{target_type: target_type, operation: operation} = command) do
    {:ok, target_type, operation} = Requests.parse(target_type, operation)
    params = OperationParams.to_map(command.params)

    case Requests.authorize(target_type, command.target_id, operation, params) do
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

  defp saved({:error, _} = error, _, _, _), do: error

  defp with_warnings({:ok, schedule}, warnings), do: {:ok, schedule, warnings}
  defp with_warnings(error, _), do: error

  # The schedule as the read model will show it, to log a change that the
  # read model does not show yet.
  defp provisional(%ScheduleOperation{} = command) do
    recurrence = Recurrence.to_map(command.recurrence) || %{}

    struct(
      OperationScheduleReadModel,
      Map.merge(recurrence, %{
        id: command.schedule_id,
        target_type: command.target_type,
        target_id: command.target_id,
        operation: command.operation,
        params: OperationParams.to_map(command.params),
        starts_at: command.starts_at,
        timezone: command.timezone,
        bulk_id: command.bulk_id
      })
    )
  end
end
