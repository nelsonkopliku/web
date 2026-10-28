# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ActivityLog.Logger.Parser.ApplicationActivityParser do
  @moduledoc """
  Application activity parser. The application hands over the actor and the
  metadata itself; without an actor the activity is attributed to the system.
  """

  @spec get_activity_actor(atom(), map()) :: String.t()
  def get_activity_actor(_activity, %{actor: actor}) when is_binary(actor), do: actor
  def get_activity_actor(_activity, _activity_context), do: "system"

  @spec get_activity_metadata(atom(), map()) :: map()
  def get_activity_metadata(_activity, %{metadata: metadata}) when is_map(metadata), do: metadata
  def get_activity_metadata(_activity, _activity_context), do: %{}
end
