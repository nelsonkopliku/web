# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Hosts.Events.HostChecksExceptionWindowRemoved do
  @moduledoc """
  The exception window of a host was removed.
  """

  use Trento.Support.Event

  defevent do
    field :host_id, Ecto.UUID
  end
end
