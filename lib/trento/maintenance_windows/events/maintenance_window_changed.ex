# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Events.MaintenanceWindowChanged do
  @moduledoc """
  The timing and the forbidden actions of a maintenance window were replaced.
  """

  use Trento.Support.Event

  require Trento.MaintenanceWindows.Enums.ForbiddenAction, as: ForbiddenAction

  alias Trento.MaintenanceWindows.ValueObjects.Recurrence

  defevent do
    field :window_id, Ecto.UUID
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    field :duration_minutes, :integer
    embeds_one :recurrence, Recurrence
    field :forbids, {:array, Ecto.Enum}, values: ForbiddenAction.values()
  end
end
