# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling.ExecutionRequest do
  @moduledoc """
  The last periodic checks execution request of a host or cluster.

  It is operational state, not an event: one event per target every few
  minutes would flood the event store.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:target_id, Ecto.UUID, autogenerate: false}
  schema "checks_execution_requests" do
    field :target_type, :string
    field :last_requested_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
