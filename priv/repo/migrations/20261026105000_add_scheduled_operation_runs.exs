# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Repo.Migrations.AddScheduledOperationRuns do
  use Ecto.Migration

  def change do
    create table(:scheduled_operation_runs, primary_key: false) do
      add :operation_id, :uuid, primary_key: true
      add :schedule_id, :uuid, null: false
      add :run_at, :utc_datetime_usec, null: false
      add :target_type, :string, null: false
      add :target_id, :uuid, null: false
      add :operation, :string, null: false
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:scheduled_operation_runs, [:schedule_id, :run_at])
  end
end
