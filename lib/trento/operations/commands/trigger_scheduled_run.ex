# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.Commands.TriggerScheduledRun do
  @moduledoc """
  The occurrence of an operation schedule at `run_at` is due: `triggered_at`
  is when the scheduler noticed it.
  """

  @required_fields :all

  use Trento.Support.Command

  defcommand do
    field :schedule_id, Ecto.UUID
    field :run_at, :utc_datetime_usec
    field :triggered_at, :utc_datetime_usec
  end
end
