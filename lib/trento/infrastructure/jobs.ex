# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Infrastructure.Jobs do
  @moduledoc """
  Oban configuration. The pruning of the discovery events, which a
  deployment can change, comes from its own configuration key, so that every
  environment sets it without repeating the whole crontab. The checks
  execution job runs every minute: `Trento.ChecksScheduling` decides which
  targets are due.
  """

  alias Trento.Infrastructure.Jobs.{ChecksExecutionJob, DiscoveryEventsPruningJob}

  @spec oban_config() :: keyword()
  def oban_config do
    pruning = Application.fetch_env!(:trento, :discovery_events_pruning)

    entries = [
      {"* * * * *", ChecksExecutionJob, queue: :checks},
      {Keyword.fetch!(pruning, :schedule), DiscoveryEventsPruningJob,
       args: %{older_than: Keyword.fetch!(pruning, :older_than)}}
    ]

    Application.fetch_env!(:trento, Oban)
    |> Keyword.update(:cron, [crontab: entries], fn cron ->
      Keyword.update(cron, :crontab, entries, &(entries ++ &1))
    end)
  end
end
