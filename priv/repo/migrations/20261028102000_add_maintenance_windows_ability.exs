# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Repo.Migrations.AddMaintenanceWindowsAbility do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO abilities(name, resource, label, inserted_at, updated_at)
    VALUES ('all', 'maintenance_windows', 'Permits all operations on maintenance windows', NOW(), NOW())
    """
  end

  def down do
    execute "DELETE FROM abilities WHERE name = 'all' AND resource = 'maintenance_windows'"
  end
end
