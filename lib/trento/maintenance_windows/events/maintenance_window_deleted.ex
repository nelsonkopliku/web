# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Events.MaintenanceWindowDeleted do
  @moduledoc """
  A maintenance window was deleted: it no longer forbids anything.
  """

  use Trento.Support.Event

  defevent do
    field :window_id, Ecto.UUID
  end
end
