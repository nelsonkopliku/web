# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Repo.Migrations.AddExceptionWindowToChecksTargetSchedules do
  use Ecto.Migration

  def change do
    alter table(:checks_target_schedules) do
      add :window_starts_at, :utc_datetime_usec
      add :window_timezone, :string
      add :window_duration_minutes, :integer
      add :window_frequency, :string
      add :window_interval, :integer
      add :window_weekdays, {:array, :integer}
    end
  end
end
