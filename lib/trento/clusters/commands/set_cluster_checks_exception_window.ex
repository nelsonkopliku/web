# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Clusters.Commands.SetClusterChecksExceptionWindow do
  @moduledoc """
  Set the exception window of a cluster: its checks are not executed
  periodically during the window. `requested_at` is when the window is
  requested: a one-time window must not be over by then.
  """

  @required_fields :all

  use Trento.Support.Command

  alias Trento.ChecksScheduling.ValueObjects.ExceptionWindow

  defcommand do
    field :cluster_id, Ecto.UUID
    embeds_one :exception_window, ExceptionWindow
    field :requested_at, :utc_datetime_usec
  end
end
