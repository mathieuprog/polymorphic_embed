defmodule PolymorphicEmbed.Channel.Email do
  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field :address, :string
    field :confirmed, :boolean
    field :valid, :boolean
  end
end
