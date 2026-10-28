# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling.PolicyTest do
  use ExUnit.Case, async: true

  alias Trento.Abilities.Ability
  alias Trento.ChecksScheduling.Policy
  alias Trento.Users.User

  @updates [:update_host_checks_schedule, :update_cluster_checks_schedule]
  @shows [:show_host_checks_schedule, :show_cluster_checks_schedule]

  test "should allow changing the interval of a target with all:all or all:check_frequency" do
    for ability <- [
          %Ability{name: "all", resource: "all"},
          %Ability{name: "all", resource: "check_frequency"}
        ],
        action <- @updates do
      assert Policy.authorize(action, %User{abilities: [ability]}, nil)
    end
  end

  test "should not allow changing the interval with other abilities" do
    for abilities <- [[%Ability{name: "all", resource: "host_checks_selection"}], []],
        action <- @updates do
      refute Policy.authorize(action, %User{abilities: abilities}, nil)
    end
  end

  test "should let every user read the interval of a target" do
    for action <- @shows, do: assert(Policy.authorize(action, %User{abilities: []}, nil))
  end
end
