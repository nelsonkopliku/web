# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Clusters.Events.ClusterChecksExceptionWindowRemoved do
  @moduledoc """
  The exception window of a cluster was removed.
  """

  use Trento.Support.Event

  defevent do
    field :cluster_id, Ecto.UUID
  end
end
