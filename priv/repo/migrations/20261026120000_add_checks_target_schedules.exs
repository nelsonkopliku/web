# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Repo.Migrations.AddChecksTargetSchedules do
  use Ecto.Migration

  def change do
    create table(:checks_target_schedules, primary_key: false) do
      add :target_id, :uuid, primary_key: true
      add :target_type, :string, null: false
      add :interval, :string
      add :last_requested_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end
  end
end
