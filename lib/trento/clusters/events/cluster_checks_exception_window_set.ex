# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Clusters.Events.ClusterChecksExceptionWindowSet do
  @moduledoc """
  The exception window of a cluster was set: its checks are not executed
  periodically during the window.
  """

  use Trento.Support.Event

  alias Trento.ChecksScheduling.ValueObjects.ExceptionWindow

  defevent do
    field :cluster_id, Ecto.UUID
    embeds_one :exception_window, ExceptionWindow
  end
end
