# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Commands.DeleteMaintenanceWindow do
  @moduledoc """
  Delete a maintenance window: it no longer forbids anything.
  """

  @required_fields :all

  use Trento.Support.Command

  defcommand do
    field :window_id, Ecto.UUID
  end
end
