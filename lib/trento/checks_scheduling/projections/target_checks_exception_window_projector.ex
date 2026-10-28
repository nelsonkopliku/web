# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling.Projections.TargetChecksExceptionWindowProjector do
  @moduledoc """
  Projects the exception window of the hosts and clusters into their own read
  model. A target without a window, or deregistered, has no row.

  The API waits for this projector after a change, so that the next read
  shows it: the projector registers for strong consistency.
  """

  use Commanded.Projections.Ecto,
    application: Trento.Commanded,
    repo: Trento.Repo,
    name: "target_checks_exception_window_projector",
    consistency: :strong

  import Ecto.Query, only: [from: 2]

  alias Trento.ChecksScheduling.Projections.TargetChecksExceptionWindowReadModel
  alias Trento.ChecksScheduling.ValueObjects.ExceptionWindow
  alias Trento.Clusters.Cluster

  alias Trento.Clusters.Events.{
    ClusterChecksExceptionWindowRemoved,
    ClusterChecksExceptionWindowSet,
    ClusterDeregistered,
    ClusterRolledUp
  }

  alias Trento.Hosts.Events.{
    HostChecksExceptionWindowRemoved,
    HostChecksExceptionWindowSet,
    HostDeregistered,
    HostRolledUp
  }

  alias Trento.Hosts.Host

  project(%HostChecksExceptionWindowSet{host_id: host_id, exception_window: window}, fn multi ->
    put(multi, host_id, "host", window)
  end)

  project(
    %ClusterChecksExceptionWindowSet{cluster_id: cluster_id, exception_window: window},
    fn multi -> put(multi, cluster_id, "cluster", window) end
  )

  project(%HostChecksExceptionWindowRemoved{host_id: host_id}, fn multi ->
    put(multi, host_id, "host", nil)
  end)

  project(%ClusterChecksExceptionWindowRemoved{cluster_id: cluster_id}, fn multi ->
    put(multi, cluster_id, "cluster", nil)
  end)

  project(%HostDeregistered{host_id: host_id}, fn multi -> put(multi, host_id, "host", nil) end)

  project(%ClusterDeregistered{cluster_id: cluster_id}, fn multi ->
    put(multi, cluster_id, "cluster", nil)
  end)

  # The events before a roll-up leave the stream: the snapshot tells the window
  project(%HostRolledUp{host_id: host_id, snapshot: %Host{} = snapshot}, fn multi ->
    put(multi, host_id, "host", snapshot_window(snapshot))
  end)

  project(%ClusterRolledUp{cluster_id: cluster_id, snapshot: %Cluster{} = snapshot}, fn multi ->
    put(multi, cluster_id, "cluster", snapshot_window(snapshot))
  end)

  defp put(multi, target_id, _, nil) do
    Ecto.Multi.delete_all(
      multi,
      :target_checks_exception_window,
      from(w in TargetChecksExceptionWindowReadModel, where: w.target_id == ^target_id)
    )
  end

  defp put(multi, target_id, target_type, %ExceptionWindow{} = window) do
    changeset =
      TargetChecksExceptionWindowReadModel.changeset(
        %TargetChecksExceptionWindowReadModel{},
        window
        |> Map.from_struct()
        |> Map.merge(%{target_id: target_id, target_type: target_type})
      )

    Ecto.Multi.insert(multi, :target_checks_exception_window, changeset,
      on_conflict:
        {:replace,
         [:starts_at, :timezone, :duration_minutes, :frequency, :interval, :weekdays, :updated_at]},
      conflict_target: :target_id
    )
  end

  defp snapshot_window(%{deregistered_at: nil, checks_exception_window: window}), do: window
  defp snapshot_window(_), do: nil
end
