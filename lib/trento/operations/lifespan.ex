# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Lifespan do
  @moduledoc """
  Operation schedule aggregate lifespan.

  A schedule handles a few commands per occurrence, hours or days apart: its
  process stops after a while without commands and is rebuilt from its short
  stream when the next command comes.
  """

  @behaviour Commanded.Aggregates.AggregateLifespan

  @idle_timeout :timer.minutes(10)

  def after_event(_event), do: @idle_timeout

  def after_command(_command), do: @idle_timeout

  def after_error(error) do
    if Kernel.is_exception(error), do: {:stop, error}, else: @idle_timeout
  end
end
