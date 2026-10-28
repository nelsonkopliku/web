# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Events.MaintenanceWindowScheduled do
  @moduledoc """
  A maintenance window was set on a target.
  """

  use Trento.Support.Event

  require Trento.MaintenanceWindows.Enums.ForbiddenAction, as: ForbiddenAction

  alias Trento.MaintenanceWindows.ValueObjects.Recurrence

  defevent do
    field :window_id, Ecto.UUID
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :starts_at, :utc_datetime_usec
    field :timezone, :string
    field :duration_minutes, :integer
    embeds_one :recurrence, Recurrence
    field :forbids, {:array, Ecto.Enum}, values: ForbiddenAction.values()
    field :bulk_id, Ecto.UUID
  end
end
