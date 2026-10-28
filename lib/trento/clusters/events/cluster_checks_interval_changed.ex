# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Clusters.Events.ClusterChecksIntervalChanged do
  @moduledoc """
  The interval of the periodic checks executions of a cluster changed, nil
  for the global interval.
  """

  use Trento.Support.Event

  defevent do
    field :cluster_id, Ecto.UUID
    field :interval, :string
  end
end
