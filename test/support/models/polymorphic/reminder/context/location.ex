defmodule PolymorphicEmbed.Reminder.Context.Location do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    belongs_to :country, PolymorphicEmbed.Country
    field :address, :string
  end

  def changeset(struct, params) do
    struct
    |> cast(params, ~w(address)a)
    |> cast_assoc(:country)
  end
end
