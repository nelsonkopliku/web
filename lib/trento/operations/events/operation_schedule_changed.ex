# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Events.OperationScheduleChanged do
  @moduledoc """
  The params and the timing of an operation schedule were replaced, and its
  occurrence count restarted. `next_run_at` is its next occurrence.
  """

  use Trento.Support.Event

  alias Trento.Operations.ValueObjects.{OperationParams, Recurrence}

  defevent do
    field :schedule_id, Ecto.UUID
    embeds_one :params, OperationParams
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    embeds_one :recurrence, Recurrence
    field :next_run_at, :utc_datetime_usec
  end
end
