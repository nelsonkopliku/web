# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Hosts.Events.HostChecksIntervalChanged do
  @moduledoc """
  The interval of the periodic checks executions of a host changed, nil for
  the global interval.
  """

  use Trento.Support.Event

  defevent do
    field :host_id, Ecto.UUID
    field :interval, :string
  end
end
