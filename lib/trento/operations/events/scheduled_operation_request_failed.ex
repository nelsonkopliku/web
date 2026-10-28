# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Events.ScheduledOperationRequestFailed do
  @moduledoc """
  The operation of the occurrence at `run_at` was not requested: Trento was
  not available in time, the target is gone, the operation policies failed,
  or a maintenance window forbids operations on the target. `occurrences` counts the occurrences handled or missed, and
  `next_run_at` is the next one, nil when the schedule ended.
  """

  use Trento.Support.Event

  alias Trento.Operations.ValueObjects.PolicyError

  defevent do
    field :schedule_id, Ecto.UUID
    field :run_at, :utc_datetime_usec

    field :reason, Ecto.Enum,
      values: [:not_available, :policies, :target_not_found, :maintenance_window]

    embeds_many :errors, PolicyError
    field :occurrences, :integer
    field :next_run_at, :utc_datetime_usec
  end
end
