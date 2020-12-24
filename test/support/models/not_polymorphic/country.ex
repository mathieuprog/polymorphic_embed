defmodule PolymorphicEmbed.Regular.Country do
  use Ecto.Schema

  schema "countries" do
    field :name, :string
    timestamps()
  end
end
