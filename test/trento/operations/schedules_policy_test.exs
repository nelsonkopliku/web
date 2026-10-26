# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.SchedulesPolicyTest do
  use ExUnit.Case, async: true

  alias Trento.Abilities.Ability
  alias Trento.Operations.{OperationSchedule, SchedulesPolicy}
  alias Trento.Users.User

  @reboot %{target_type: "host", operation: "reboot"}

  test "should let every user list schedules" do
    assert SchedulesPolicy.authorize(:index, %User{abilities: []}, nil)
  end

  test "should require the ability of the operation to schedule, change or cancel it" do
    allowed = %User{abilities: [%Ability{name: "reboot", resource: "host"}]}
    admin = %User{abilities: [%Ability{name: "all", resource: "all"}]}
    other = %User{abilities: [%Ability{name: "all", resource: "host_checks_selection"}]}

    for action <- [:create, :update, :delete] do
      assert SchedulesPolicy.authorize(action, allowed, @reboot)
      assert SchedulesPolicy.authorize(action, admin, struct(OperationSchedule, @reboot))
      refute SchedulesPolicy.authorize(action, other, @reboot)
    end
  end

  test "should leave a missing schedule and a wrong operation to the action" do
    user = %User{abilities: []}

    assert SchedulesPolicy.authorize(:update, user, nil)
    assert SchedulesPolicy.authorize(:delete, user, nil)

    assert SchedulesPolicy.authorize(:create, user, %{target_type: "cluster", operation: "reboot"})
  end
end
