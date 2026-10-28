# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule TrentoWeb.V1.ChecksScheduleJSON do
  def checks_schedule(%{checks_schedule: checks_schedule}),
    do:
      Map.take(checks_schedule, [
        :interval,
        :effective_interval,
        :global_interval,
        :last_requested_at,
        :next_execution_at,
        :exception_window,
        :in_exception_window
      ])
end
