# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Events.ScheduledRunStarted do
  @moduledoc """
  The run of the occurrence at `run_at` started: the operation is to be
  requested with this operation id, the same each time the run starts again.
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
    field :started_at, :utc_datetime_usec
  end
end
