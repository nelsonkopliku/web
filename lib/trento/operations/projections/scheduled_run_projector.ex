# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Projections.ScheduledRunProjector do
  @moduledoc """
  Records each operation requested by a schedule in scheduled_operation_runs,
  see `Trento.Operations.ScheduledRuns`: the reply of Wanda names the
  operation id only, the run tells which schedule and occurrence it belongs
  to. A run is recorded once.

  The scheduler waits for this projector after recording the outcome of a
  run, so that the run is recorded at once for the reply of Wanda: the
  projector registers for strong consistency.
  """

  use Commanded.Projections.Ecto,
    application: Trento.Commanded,
    repo: Trento.Repo,
    name: "scheduled_run_projector",
    consistency: :strong

  alias Trento.Operations.Events.ScheduledOperationRequested
  alias Trento.Operations.ScheduledRuns
  alias Trento.Operations.ValueObjects.OperationParams

  project(%ScheduledOperationRequested{} = event, fn multi ->
    changeset =
      ScheduledRuns.changeset(%{
        operation_id: event.operation_id,
        schedule_id: event.schedule_id,
        run_at: event.run_at,
        target_type: event.target_type,
        target_id: event.target_id,
        operation: event.operation,
        params: OperationParams.to_map(event.params)
      })

    Ecto.Multi.insert(multi, :scheduled_run, changeset, on_conflict: :nothing)
  end)
end
