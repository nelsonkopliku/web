# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.PolicyTest do
  use ExUnit.Case, async: true

  alias Trento.Abilities.Ability
  alias Trento.MaintenanceWindows.Policy
  alias Trento.Users.User

  @changes [:create, :bulk_create, :update, :delete]

  test "should let every user list the windows" do
    assert Policy.authorize(:index, %User{abilities: []}, nil)
  end

  test "should require all:all or all:maintenance_windows to change windows" do
    for ability <- [
          %Ability{name: "all", resource: "all"},
          %Ability{name: "all", resource: "maintenance_windows"}
        ],
        action <- @changes do
      assert Policy.authorize(action, %User{abilities: [ability]}, nil)
    end

    for abilities <- [[%Ability{name: "all", resource: "check_frequency"}], []],
        action <- @changes do
      refute Policy.authorize(action, %User{abilities: abilities}, nil)
    end
  end
end
