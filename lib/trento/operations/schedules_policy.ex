# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.SchedulesPolicy do
  @moduledoc """
  Policy of the operation schedules.

  Scheduling, changing or cancelling an operation requires the same ability
  as requesting it immediately. A target type and operation that cannot be
  scheduled together are left to the validation of the schedule.
  """

  @behaviour Bodyguard.Policy

  alias Trento.Operations.Requests
  alias Trento.Users.User

  def authorize(:index, _, _), do: true

  def authorize(action, %User{} = user, %{target_type: target_type, operation: operation})
      when action in [:create, :bulk_create, :update, :delete] do
    case Requests.parse(target_type, operation) do
      {:ok, target_type, operation} -> Requests.allowed?(user, target_type, operation)
      :error -> true
    end
  end

  def authorize(action, _, nil) when action in [:update, :delete], do: true

  def authorize(_, _, _), do: false
end
