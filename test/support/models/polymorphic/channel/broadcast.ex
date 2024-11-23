defmodule PolymorphicEmbed.Channel.Broadcast do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    # A schema with no fields
  end

  def changeset(broadcast, params) do
    cast(broadcast, params, ~w()a)
  end
end
