# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ValueObjects.PolicyError do
  @moduledoc """
  An operation policy that did not pass, and the resources it is about, see
  `Trento.Support.OperationsHelper.forbidden_error/0`.
  """

  @required_fields [:message]

  use Trento.Support.Type

  alias Trento.Operations.ValueObjects.PolicyErrorResource

  deftype do
    field :message, :string
    embeds_many :metadata, PolicyErrorResource
  end
end
