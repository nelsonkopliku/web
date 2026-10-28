# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Infrastructure.Jobs.ScheduleJobsReconciliationJob do
  @moduledoc """
  Gives a job back to the operation schedules that lost theirs, see
  `Trento.Operations.Scheduler.reconcile/1`.
  """

  use Oban.Worker, queue: :operations, max_attempts: 1

  @impl Oban.Worker
  def perform(_job), do: Trento.Operations.Scheduler.reconcile()
end
