# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Events.OperationScheduleCancelled do
  @moduledoc """
  An operation schedule was cancelled: it no longer runs.
  """

  use Trento.Support.Event

  defevent do
    field :schedule_id, Ecto.UUID
  end
end
