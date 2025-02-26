defmodule Trento.Domain.HanaClusterNode do
  @moduledoc """
  Represents the node of a HANA cluster.
  """

  @required_fields [
    :name,
    :site,
    :hana_status,
    :attributes
  ]

  use Trento.Type

  alias Trento.Domain.ClusterResource

  deftype do
    field :name, :string
    field :site, :string
    field :hana_status, :string
    field :attributes, {:map, :string}
    field :virtual_ip, :string

    embeds_many :resources, ClusterResource
  end
end
