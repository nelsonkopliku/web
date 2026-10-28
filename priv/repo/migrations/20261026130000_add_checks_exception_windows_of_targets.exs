# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Repo.Migrations.AddChecksExceptionWindowsOfTargets do
  use Ecto.Migration

  def change do
    create table(:target_checks_exception_windows, primary_key: false) do
      add :target_id, :uuid, primary_key: true
      add :target_type, :string, null: false
      add :starts_at, :utc_datetime_usec, null: false
      add :timezone, :string, null: false
      add :duration_minutes, :integer, null: false
      add :frequency, :string
      add :interval, :integer
      add :weekdays, {:array, :integer}

      timestamps(type: :utc_datetime_usec)
    end
  end
end
