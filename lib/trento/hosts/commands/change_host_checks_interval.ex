# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Hosts.Commands.ChangeHostChecksInterval do
  @moduledoc """
  Set the interval of the periodic checks executions of a host, nil for the
  global interval.
  """

  @required_fields [:host_id]

  use Trento.Support.Command

  alias Trento.ChecksScheduling.Interval

  defcommand do
    field :host_id, Ecto.UUID
    field :interval, :string
  end

  def changeset(command, params) do
    command
    |> super(params)
    |> Interval.validate(:interval)
  end
end
