# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Lifespan do
  @moduledoc """
  Maintenance window aggregate lifespan.

  A window handles a few commands in its life: its process stops after a
  while without commands and is rebuilt from its short stream when the next
  command comes. A deleted window stops at once.
  """

  @behaviour Commanded.Aggregates.AggregateLifespan

  alias Trento.MaintenanceWindows.Events.MaintenanceWindowDeleted

  @idle_timeout :timer.minutes(10)

  def after_event(%MaintenanceWindowDeleted{}), do: :stop
  def after_event(_event), do: @idle_timeout

  def after_command(_command), do: @idle_timeout

  def after_error(error) do
    if Kernel.is_exception(error), do: {:stop, error}, else: @idle_timeout
  end
end
