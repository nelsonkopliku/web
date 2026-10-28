# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Projections.OperationScheduleProjector do
  @moduledoc """
  Projects the operation schedules into the operation_schedules read model.

  The schedules API waits for this projector after a change, so that it
  answers with the projected schedule: the projector registers for strong
  consistency, and the API dispatches with `consistency: [__MODULE__]`. The
  UI is told that the schedules of the target changed.
  """

  use Commanded.Projections.Ecto,
    application: Trento.Commanded,
    repo: Trento.Repo,
    name: "operation_schedule_projector",
    consistency: :strong

  alias Trento.Operations.Events.{OperationScheduleChanged, OperationScheduled}
  alias Trento.Operations.Projections.OperationScheduleReadModel
  alias Trento.Operations.ValueObjects.{OperationParams, Recurrence}
  alias Trento.Repo

  @topic "monitoring:operation_schedules"

  project(%OperationScheduled{} = event, metadata, fn multi ->
    changeset =
      OperationScheduleReadModel.changeset(
        %OperationScheduleReadModel{},
        event
        |> timing()
        |> Map.merge(%{
          id: event.schedule_id,
          target_type: event.target_type,
          target_id: event.target_id,
          operation: event.operation,
          bulk_id: event.bulk_id,
          created_by: Map.get(metadata, "created_by")
        })
      )

    Ecto.Multi.insert(multi, :operation_schedule, changeset)
  end)

  project(%OperationScheduleChanged{schedule_id: schedule_id} = event, fn multi ->
    changeset =
      OperationScheduleReadModel
      |> Repo.get!(schedule_id)
      |> OperationScheduleReadModel.changeset(timing(event))

    Ecto.Multi.update(multi, :operation_schedule, changeset)
  end)

  @impl true
  def after_update(_event, _metadata, %{
        operation_schedule: %OperationScheduleReadModel{target_id: target_id}
      }) do
    TrentoWeb.Endpoint.broadcast(@topic, "operation_schedules_changed", %{target_id: target_id})
  end

  def after_update(_event, _metadata, _changes), do: :ok

  # The params and the timing of a schedule, as the read model keeps them.
  defp timing(%{recurrence: recurrence} = event) do
    Map.merge(
      %{
        params: OperationParams.to_map(event.params),
        starts_at: event.starts_at,
        timezone: event.timezone,
        next_run_at: event.next_run_at,
        occurrences: 0
      },
      recurrence_fields(recurrence)
    )
  end

  defp recurrence_fields(nil),
    do: %{frequency: nil, interval: 1, weekdays: [], ends_on: nil, max_occurrences: nil}

  defp recurrence_fields(%Recurrence{} = recurrence), do: Recurrence.to_map(recurrence)
end
