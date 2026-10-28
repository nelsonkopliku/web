# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.Operations.ValueObjects.OperationParams do
  @moduledoc """
  The params of a scheduled operation: the params of its immediate request.
  SAP instance operations target the SAP system and name the instance with
  `host_id` and `instance_number`.

  Which params an operation takes is validated with the schema of its
  immediate request when the schedule is saved; an operation ignores the
  params it does not take.
  """

  @required_fields []

  use Trento.Support.Type

  @fields [
    :maintenance,
    :resource_id,
    :node_id,
    :instance_type,
    :host_id,
    :instance_number,
    :site,
    :timeout
  ]

  deftype do
    field :maintenance, :boolean
    field :resource_id, :string
    field :node_id, :string
    field :instance_type, :string
    field :host_id, Ecto.UUID
    field :instance_number, :string
    field :site, :string
    field :timeout, :integer
  end

  def changeset(params, attrs), do: cast(params, attrs, @fields)

  @doc """
  The params that are set, as a map with atom keys.
  """
  @spec to_map(t() | nil) :: map()
  def to_map(nil), do: %{}

  def to_map(%__MODULE__{} = params) do
    params
    |> Map.take(@fields)
    |> Map.reject(fn {_, value} -> is_nil(value) end)
  end
end
