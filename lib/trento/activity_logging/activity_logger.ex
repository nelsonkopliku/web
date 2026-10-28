# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ActivityLog.ActivityLogger do
  @moduledoc """
  ActivityLogger entry point
  """

  alias Trento.Repo

  alias Trento.ActivityLog.ActivityCatalog
  alias Trento.ActivityLog.ActivityLog
  alias Trento.ActivityLog.Parser.ActivityParser

  require Logger

  @doc """
  Logs an activity that the application emits itself (see
  `Trento.ActivityLog.ActivityCatalog.application_activities/0`). Logging never
  raises: a failure is reported in the log only.
  """
  @spec log_application_activity(atom(), String.t(), map()) :: :ok
  def log_application_activity(activity, actor, metadata),
    do: log_activity(%{application_activity: activity, actor: actor, metadata: metadata})

  def log_activity(activity_context) do
    with {:ok, detected_activity} <- ActivityCatalog.detect_activity(activity_context),
         {:ok, log_entry} <- ActivityParser.to_activity_log(detected_activity, activity_context) do
      write_log(log_entry)
    end

    :ok
  end

  defp write_log(%{type: activity_type} = entry) do
    case %ActivityLog{}
         |> ActivityLog.changeset(entry)
         |> Repo.insert() do
      {:ok, _} ->
        Logger.info("Logged activity: #{activity_type}")

      {:error, reason} ->
        Logger.error(
          "An error occurred while logging activity: #{activity_type}. Reason: #{inspect(reason)}"
        )
    end
  end
end
