# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling.Projections.TargetChecksIntervalProjector do
  @moduledoc """
  Projects the checks execution interval of the hosts and clusters into their
  own read model, so that the host and cluster read models and their API stay
  as they are. A target that uses the global interval, or that is
  deregistered, has no row.

  The API waits for this projector after a change, so that the next read
  shows it: the projector registers for strong consistency.
  """

  use Commanded.Projections.Ecto,
    application: Trento.Commanded,
    repo: Trento.Repo,
    name: "target_checks_interval_projector",
    consistency: :strong

  import Ecto.Query, only: [from: 2]

  alias Trento.ChecksScheduling.Projections.TargetChecksIntervalReadModel
  alias Trento.Clusters.Cluster

  alias Trento.Clusters.Events.{
    ClusterChecksIntervalChanged,
    ClusterDeregistered,
    ClusterRolledUp
  }

  alias Trento.Hosts.Events.{HostChecksIntervalChanged, HostDeregistered, HostRolledUp}
  alias Trento.Hosts.Host

  project(%HostChecksIntervalChanged{host_id: host_id, interval: interval}, fn multi ->
    put(multi, host_id, "host", interval)
  end)

  project(%ClusterChecksIntervalChanged{cluster_id: cluster_id, interval: interval}, fn multi ->
    put(multi, cluster_id, "cluster", interval)
  end)

  project(%HostDeregistered{host_id: host_id}, fn multi -> put(multi, host_id, "host", nil) end)

  project(%ClusterDeregistered{cluster_id: cluster_id}, fn multi ->
    put(multi, cluster_id, "cluster", nil)
  end)

  # The events before a roll-up leave the stream: the snapshot tells the interval
  project(%HostRolledUp{host_id: host_id, snapshot: %Host{} = snapshot}, fn multi ->
    put(multi, host_id, "host", snapshot_interval(snapshot))
  end)

  project(%ClusterRolledUp{cluster_id: cluster_id, snapshot: %Cluster{} = snapshot}, fn multi ->
    put(multi, cluster_id, "cluster", snapshot_interval(snapshot))
  end)

  defp put(multi, target_id, _, nil) do
    Ecto.Multi.delete_all(
      multi,
      :target_checks_interval,
      from(i in TargetChecksIntervalReadModel, where: i.target_id == ^target_id)
    )
  end

  defp put(multi, target_id, target_type, interval) do
    changeset =
      TargetChecksIntervalReadModel.changeset(%TargetChecksIntervalReadModel{}, %{
        target_id: target_id,
        target_type: target_type,
        interval: interval
      })

    Ecto.Multi.insert(multi, :target_checks_interval, changeset,
      on_conflict: {:replace, [:interval, :updated_at]},
      conflict_target: :target_id
    )
  end

  defp snapshot_interval(%{deregistered_at: nil, checks_interval: interval}), do: interval
  defp snapshot_interval(_), do: nil
end
