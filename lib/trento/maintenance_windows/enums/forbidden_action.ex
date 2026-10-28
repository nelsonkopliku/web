# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Enums.ForbiddenAction do
  @moduledoc """
  Actions a maintenance window can forbid on the targets it covers.
  """
  use Trento.Support.Enum, values: [:checks_execution, :operations]
end
