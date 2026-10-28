# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ValueObjects.PendingRun do
  @moduledoc """
  The run of an occurrence whose outcome is not recorded yet: when it
  started, and the request it made, with its operation id.
  """

  @required_fields :all

  use Trento.Support.Type

  alias Trento.Operations.ValueObjects.OperationParams

  deftype do
    field :run_at, :utc_datetime_usec
    field :operation_id, Ecto.UUID
    embeds_one :params, OperationParams
    field :started_at, :utc_datetime_usec
  end
end
