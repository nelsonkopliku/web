# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Repo.Migrations.AddMaintenanceWindowCoverageIndexes do
  use Ecto.Migration

  # The coverage of maintenance windows walks from hosts to their cluster and
  # from databases to their SAP systems.
  def change do
    create_if_not_exists index(:hosts, [:cluster_id])
    create_if_not_exists index(:sap_systems, [:database_id])
  end
end
