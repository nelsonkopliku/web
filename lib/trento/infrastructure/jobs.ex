# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Infrastructure.Jobs do
  @moduledoc """
  Oban configuration. The crontab entries that a deployment can change come
  from their own configuration keys, so that every environment sets them
  without repeating the whole crontab: the checks execution and the pruning
  of the discovery events.
  """

  alias Trento.Infrastructure.Jobs.{ChecksExecutionJob, DiscoveryEventsPruningJob}

  @spec oban_config() :: keyword()
  def oban_config do
    checks_cron = Application.fetch_env!(:trento, :checks_execution_cron)
    pruning = Application.fetch_env!(:trento, :discovery_events_pruning)

    entries = [
      {checks_cron, ChecksExecutionJob, queue: :checks},
      {Keyword.fetch!(pruning, :schedule), DiscoveryEventsPruningJob,
       args: %{older_than: Keyword.fetch!(pruning, :older_than)}}
    ]

    Application.fetch_env!(:trento, Oban)
    |> Keyword.update(:cron, [crontab: entries], fn cron ->
      Keyword.update(cron, :crontab, entries, &(entries ++ &1))
    end)
  end
end
