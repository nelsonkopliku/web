# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ValueObjects.PolicyErrorResource do
  @moduledoc """
  A resource that an operation policy error names.
  """

  @required_fields [:id, :type]

  use Trento.Support.Type

  deftype do
    field :id, :string
    field :label, :string
    field :type, Ecto.Enum, values: [:host, :cluster, :sap_system, :database]
  end
end
