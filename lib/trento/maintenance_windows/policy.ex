# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.MaintenanceWindows.Policy do
  @moduledoc """
  Policy of the maintenance windows. Every user sees them. Scheduling,
  changing and deleting them requires the all:maintenance_windows ability.
  """

  @behaviour Bodyguard.Policy

  import Trento.Support.AbilitiesHelper

  alias Trento.Users.User

  def authorize(:index, _, _), do: true

  def authorize(action, %User{} = user, _)
      when action in [:create, :bulk_create, :update, :delete],
      do:
        has_global_ability?(user) or
          user_has_ability?(user, %{name: "all", resource: "maintenance_windows"})

  def authorize(_, _, _), do: false
end
