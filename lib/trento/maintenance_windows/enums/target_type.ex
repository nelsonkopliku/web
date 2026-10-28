# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Enums.TargetType do
  @moduledoc """
  Targets a maintenance window can be set on.
  """
  use Trento.Support.Enum, values: [:host, :cluster, :database, :sap_system]
end
