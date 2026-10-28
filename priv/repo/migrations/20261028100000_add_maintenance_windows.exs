# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Repo.Migrations.AddMaintenanceWindows do
  use Ecto.Migration

  def change do
    create table(:maintenance_windows, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :target_type, :string, null: false
      add :target_id, :uuid, null: false
      add :starts_at, :utc_datetime_usec, null: false
      add :timezone, :string, null: false
      add :duration_minutes, :integer, null: false
      add :frequency, :string
      add :interval, :integer, null: false, default: 1
      add :weekdays, {:array, :integer}, null: false, default: []
      add :ends_on, :date
      add :forbid_checks_execution, :boolean, null: false, default: false
      add :forbid_operations, :boolean, null: false, default: false
      add :bulk_id, :uuid
      add :created_by, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:maintenance_windows, [:target_id])

    create constraint(:maintenance_windows, :forbids_an_action,
             check: "forbid_checks_execution OR forbid_operations"
           )
  end
end
