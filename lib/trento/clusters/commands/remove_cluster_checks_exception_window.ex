# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Clusters.Commands.RemoveClusterChecksExceptionWindow do
  @moduledoc """
  Remove the exception window of a cluster.
  """

  @required_fields :all

  use Trento.Support.Command

  defcommand do
    field :cluster_id, Ecto.UUID
  end
end
