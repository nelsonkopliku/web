# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Repo.Migrations.AddCheckFrequencyAbility do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO abilities(name, resource, label, inserted_at, updated_at)
    VALUES ('all', 'check_frequency', 'Permits all operations on the check execution frequency of hosts and clusters', NOW(), NOW())
    """
  end

  def down do
    execute "DELETE FROM abilities WHERE name = 'all' AND resource = 'check_frequency'"
  end
end
