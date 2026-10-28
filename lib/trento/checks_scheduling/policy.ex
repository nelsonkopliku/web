# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ChecksScheduling.Policy do
  @moduledoc """
  Policy of the checks execution settings of hosts and clusters. Changing the
  interval of a target requires the all:check_frequency ability.
  """

  @behaviour Bodyguard.Policy

  import Trento.Support.AbilitiesHelper

  alias Trento.Users.User

  def authorize(action, %User{} = user, _)
      when action in [:update_host_checks_schedule, :update_cluster_checks_schedule],
      do:
        has_global_ability?(user) or
          user_has_ability?(user, %{name: "all", resource: "check_frequency"})

  def authorize(action, _, _)
      when action in [:show_host_checks_schedule, :show_cluster_checks_schedule],
      do: true

  def authorize(_, _, _), do: false
end
