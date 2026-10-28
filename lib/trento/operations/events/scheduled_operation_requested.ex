# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Events.ScheduledOperationRequested do
  @moduledoc """
  The operation of the occurrence at `run_at` was requested with this
  operation id. `occurrences` counts the occurrences handled or missed, and
  `next_run_at` is the next one, nil when the schedule ended.
  """

  use Trento.Support.Event

  alias Trento.Operations.ValueObjects.OperationParams

  defevent do
    field :schedule_id, Ecto.UUID
    field :run_at, :utc_datetime_usec
    field :operation_id, Ecto.UUID
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :operation, :string
    embeds_one :params, OperationParams
    field :occurrences, :integer
    field :next_run_at, :utc_datetime_usec
  end
end
