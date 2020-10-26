defmodule PolymorphicEmbed.Country do
  use Ecto.Schema

  schema "countries" do
    field :name, :string
    timestamps()
  end
end
