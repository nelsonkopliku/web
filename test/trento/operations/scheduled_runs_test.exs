# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ScheduledRunsTest do
  use ExUnit.Case, async: true
  use Trento.DataCase

  import Trento.Factory

  alias Trento.ActivityLog.ActivityLog
  alias Trento.Operations.{ScheduledRun, ScheduledRuns}

  test "should record a run once per schedule and occurrence" do
    attrs = %{
      operation_id: UUID.uuid4(),
      schedule_id: UUID.uuid4(),
      run_at: ~U[2026-11-02 02:00:00.000000Z],
      target_type: "host",
      target_id: UUID.uuid4(),
      operation: "reboot",
      params: %{}
    }

    assert {:ok, %ScheduledRun{}} = attrs |> ScheduledRuns.changeset() |> Repo.insert()

    assert {:error, %Ecto.Changeset{errors: [schedule_id: _]}} =
             attrs
             |> Map.put(:operation_id, UUID.uuid4())
             |> ScheduledRuns.changeset()
             |> Repo.insert()

    assert %ScheduledRun{schedule_id: schedule_id} =
             ScheduledRuns.get_by_operation_id(attrs.operation_id)

    assert schedule_id == attrs.schedule_id
    assert nil == ScheduledRuns.get_by_operation_id(UUID.uuid4())
    assert nil == ScheduledRuns.get_by_operation_id("not an id")
  end

  test "should name the target of a schedule for the activity log" do
    id = UUID.uuid4()

    assert %{host_id: id} == ScheduledRuns.target_metadata("host", id)
    assert %{cluster_id: id} == ScheduledRuns.target_metadata(:cluster, id)
    assert %{sap_system_id: id} == ScheduledRuns.target_metadata("sap_system", id)
    assert %{database_id: id} == ScheduledRuns.target_metadata("database", id)
  end

  test "should log the refusal of a scheduled request by Wanda" do
    %{id: host_id, hostname: hostname} = insert(:host)

    %{operation_id: operation_id, schedule_id: schedule_id} =
      insert(:scheduled_run, target_id: host_id)

    :ok =
      ScheduledRuns.record_reply(
        build(:operation_completed_with_failed_request_v1,
          operation_id: operation_id,
          error: :ALREADY_RUNNING
        )
      )

    assert [
             %ActivityLog{
               type: "scheduled_operation_request_failed",
               actor: "system",
               metadata: %{
                 "reason" => "already_running",
                 "correlation_id" => ^schedule_id,
                 "host_id" => ^host_id,
                 "hostname" => ^hostname
               }
             }
           ] = Repo.all(ActivityLog)
  end

  test "should ignore the other replies and the requests that no schedule made" do
    %{operation_id: operation_id} = insert(:scheduled_run)

    :ok =
      ScheduledRuns.record_reply(
        build(:operation_completed_with_failed_request_v1,
          operation_id: operation_id,
          error: :TARGETS_MISSING
        )
      )

    :ok =
      ScheduledRuns.record_reply(
        build(:operation_completed_with_failed_request_v1, error: :ALREADY_RUNNING)
      )

    :ok = ScheduledRuns.record_reply(build(:operation_completed_v1, operation_id: operation_id))

    assert [] == Repo.all(ActivityLog)
  end
end
