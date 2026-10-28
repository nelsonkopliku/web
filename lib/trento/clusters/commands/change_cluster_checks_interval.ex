# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Clusters.Commands.ChangeClusterChecksInterval do
  @moduledoc """
  Set the interval of the periodic checks executions of a cluster, nil for
  the global interval.
  """

  @required_fields [:cluster_id]

  use Trento.Support.Command

  alias Trento.ChecksScheduling.Interval

  defcommand do
    field :cluster_id, Ecto.UUID
    field :interval, :string
  end

  def changeset(command, params) do
    command
    |> super(params)
    |> Interval.validate(:interval)
  end
end
