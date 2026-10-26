# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ScheduledRuns do
  @moduledoc """
  The operations requested by schedules, and what Wanda answered.

  Every scheduler implementation records a run when it requests the operation
  of an occurrence. A run is unique per schedule and occurrence.

  Wanda refuses a request when another operation runs on the same target and
  replies with OperationCompleted REQUEST_FAILED/ALREADY_RUNNING. For a
  scheduled request this is a failed scheduled request, logged as such and
  correlated to the schedule.
  """

  alias Trento.ActivityLog.ActivityLogger
  alias Trento.Operations.ScheduledRun
  alias Trento.Operations.V1.{OperationCompleted, OperationRequestFailedDetails}
  alias Trento.Repo

  @doc """
  The changeset that records a run, to insert in the transaction that requests it.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: ScheduledRun.changeset(%ScheduledRun{}, attrs)

  @spec get_by_operation_id(String.t()) :: ScheduledRun.t() | nil
  def get_by_operation_id(operation_id) do
    case Ecto.UUID.cast(operation_id) do
      {:ok, uuid} -> Repo.get(ScheduledRun, uuid)
      :error -> nil
    end
  end

  @doc """
  The activity log metadata that names the target of a schedule, so that the
  activity log adds the host name, cluster name or SID.
  """
  @spec target_metadata(String.t() | atom(), String.t()) :: map()
  def target_metadata(target_type, target_id), do: %{target_key(target_type) => target_id}

  @doc """
  The activity log metadata of a run, correlated to its schedule.
  """
  @spec activity_metadata(ScheduledRun.t()) :: map()
  def activity_metadata(%ScheduledRun{} = run) do
    run.target_type
    |> target_metadata(run.target_id)
    |> Map.merge(%{
      correlation_id: run.schedule_id,
      schedule_id: run.schedule_id,
      operation_id: run.operation_id,
      operation: run.operation,
      params: run.params,
      run_at: run.run_at
    })
  end

  @doc """
  Logs a Wanda refusal of a scheduled request. Any other reply is not about a
  scheduled request failure and is ignored.
  """
  @spec record_reply(struct()) :: :ok
  def record_reply(%OperationCompleted{
        operation_id: operation_id,
        details:
          {:request_failed_details, %OperationRequestFailedDetails{error: :ALREADY_RUNNING}}
      }) do
    case get_by_operation_id(operation_id) do
      %ScheduledRun{} = run ->
        ActivityLogger.log_application_activity(
          :scheduled_operation_request_failed,
          "system",
          Map.put(activity_metadata(run), :reason, "already_running")
        )

      nil ->
        :ok
    end
  end

  def record_reply(_), do: :ok

  defp target_key(target_type) when is_atom(target_type),
    do: target_key(Atom.to_string(target_type))

  defp target_key("host"), do: :host_id
  defp target_key("cluster"), do: :cluster_id
  defp target_key("sap_system"), do: :sap_system_id
  defp target_key("database"), do: :database_id
end
