# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows do
  @moduledoc """
  Maintenance windows (TRNT-4774): one-time or periodic time slots in which
  Trento does not execute checks, or does not run operations, on a target
  and on the targets it covers.
  """

  import Ecto.Query, only: [from: 2]

  alias Trento.Clusters.Projections.ClusterReadModel
  alias Trento.Databases.Projections.DatabaseReadModel
  alias Trento.Hosts.Projections.HostReadModel
  alias Trento.MaintenanceWindows.{MaintenanceWindow, WindowActivity}
  alias Trento.Repo
  alias Trento.SapSystems.Projections.SapSystemReadModel
  alias Trento.Support.DateService

  @doc """
  Sets a maintenance window on a registered target.
  """
  @spec create_window(map(), String.t(), module()) ::
          {:ok, MaintenanceWindow.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def create_window(attrs, actor, date_service \\ DateService) do
    changeset =
      MaintenanceWindow.changeset(
        %MaintenanceWindow{},
        Map.put(attrs, :created_by, actor),
        date_service.utc_now()
      )

    with {:ok, window} <- Ecto.Changeset.apply_action(changeset, :insert),
         :ok <- registered(window.target_type, window.target_id),
         {:ok, window} <- Repo.insert(changeset) do
      WindowActivity.record(:maintenance_window_scheduled, window, actor)
      {:ok, window}
    end
  end

  @doc """
  Tells whether a target is registered: a window can only be set on one.
  """
  @spec registered(String.t(), String.t()) :: :ok | {:error, :not_found}
  def registered(target_type, target_id) do
    query =
      from t in read_model(target_type),
        where: t.id == ^target_id and is_nil(t.deregistered_at),
        select: true

    if Repo.exists?(query), do: :ok, else: {:error, :not_found}
  end

  defp read_model("host"), do: HostReadModel
  defp read_model("cluster"), do: ClusterReadModel
  defp read_model("database"), do: DatabaseReadModel
  defp read_model("sap_system"), do: SapSystemReadModel
end
