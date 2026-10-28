# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Projections.ScheduledRunProjectorTest do
  use ExUnit.Case
  use Trento.DataCase

  alias Trento.Operations.Events.ScheduledOperationRequested
  alias Trento.Operations.Projections.ScheduledRunProjector
  alias Trento.Operations.ScheduledRun
  alias Trento.Operations.ValueObjects.OperationParams
  alias Trento.ProjectorTestHelper

  @moduletag :integration

  test "should record a scheduled run once" do
    schedule_id = UUID.uuid4()
    operation_id = UUID.uuid4()
    target_id = UUID.uuid4()
    host_id = UUID.uuid4()

    event = %ScheduledOperationRequested{
      schedule_id: schedule_id,
      run_at: ~U[2026-11-07 02:00:00.000000Z],
      operation_id: operation_id,
      target_type: "sap_system",
      target_id: target_id,
      operation: "sap_instance_stop",
      params: %OperationParams{host_id: host_id, instance_number: "00"},
      occurrences: 1,
      next_run_at: nil
    }

    for _ <- 1..2 do
      ProjectorTestHelper.project(ScheduledRunProjector, event, "scheduled_run_projector")
    end

    assert [
             %ScheduledRun{
               operation_id: ^operation_id,
               schedule_id: ^schedule_id,
               run_at: ~U[2026-11-07 02:00:00.000000Z],
               target_type: "sap_system",
               target_id: ^target_id,
               operation: "sap_instance_stop",
               params: %{"host_id" => ^host_id, "instance_number" => "00"}
             }
           ] = Repo.all(ScheduledRun)
  end
end
