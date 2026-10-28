# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Commands.Timing do
  @moduledoc """
  The validation of the timing and the forbidden actions of a maintenance
  window, shared by the commands that schedule and change one.
  """

  import Ecto.Changeset

  @max_duration_minutes 31 * 24 * 60

  @spec validate(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def validate(changeset, params) do
    changeset
    |> validate_number(:duration_minutes,
      greater_than: 0,
      less_than_or_equal_to: @max_duration_minutes
    )
    |> validate_change(:timezone, fn :timezone, timezone ->
      if Tzdata.zone_exists?(timezone), do: [], else: [timezone: "is not a valid timezone"]
    end)
    |> validate_length(:forbids,
      min: 1,
      message: "must forbid checks executions, operations or both"
    )
    |> validate_occurrences_count(params)
  end

  defp validate_occurrences_count(changeset, params) do
    recurrence = Map.get(params, :recurrence) || Map.get(params, "recurrence") || %{}

    if Map.get(recurrence, :max_occurrences) || Map.get(recurrence, "max_occurrences"),
      do: add_error(changeset, :max_occurrences, "is not supported for maintenance windows"),
      else: changeset
  end
end
