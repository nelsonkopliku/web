# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Commands.ScheduleOperation do
  @moduledoc """
  Schedule an operation on a target, once or periodically, from `starts_at`
  in the local time of `timezone`.

  `requested_at` is when the schedule is requested: the schedule must start
  after it.
  """

  @required_fields [
    :schedule_id,
    :target_type,
    :target_id,
    :operation,
    :params,
    :starts_at,
    :timezone,
    :requested_at
  ]

  use Trento.Support.Command

  alias Trento.Operations.Requests
  alias Trento.Operations.ValueObjects.{OperationParams, Recurrence}

  defcommand do
    field :schedule_id, Ecto.UUID
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :operation, :string
    embeds_one :params, OperationParams
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    embeds_one :recurrence, Recurrence
    field :bulk_id, Ecto.UUID
    field :requested_at, :utc_datetime_usec
  end

  def changeset(command, params) do
    command
    |> super(params)
    |> validate_inclusion(:target_type, Requests.target_type_names())
    |> validate_schedulable()
    |> validate_change(:timezone, fn :timezone, timezone ->
      if Tzdata.zone_exists?(timezone), do: [], else: [timezone: "is not a valid timezone"]
    end)
  end

  defp validate_schedulable(changeset) do
    with target_type when is_binary(target_type) <- get_field(changeset, :target_type),
         operation when is_binary(operation) <- get_field(changeset, :operation),
         :error <- Requests.parse(target_type, operation) do
      add_error(changeset, :operation, "cannot be scheduled on this target")
    else
      _ -> changeset
    end
  end
end
