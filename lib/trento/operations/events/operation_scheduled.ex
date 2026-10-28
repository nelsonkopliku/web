# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Events.OperationScheduled do
  @moduledoc """
  An operation is scheduled on a target. `next_run_at` is its first occurrence.
  """

  use Trento.Support.Event

  alias Trento.Operations.ValueObjects.{OperationParams, Recurrence}

  defevent do
    field :schedule_id, Ecto.UUID
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :operation, :string
    embeds_one :params, OperationParams
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    embeds_one :recurrence, Recurrence
    field :next_run_at, :utc_datetime_usec
    field :bulk_id, Ecto.UUID
  end
end
