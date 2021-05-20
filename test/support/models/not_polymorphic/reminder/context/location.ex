defmodule PolymorphicEmbed.Regular.Reminder.Context.Location do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    embeds_one(:country, PolymorphicEmbed.Regular.Country, on_replace: :update)
    field :address, :string
  end

  def changeset(struct, params) do
    struct
    |> cast(params, ~w(address)a)
    |> validate_required(~w(address)a)
    |> cast_embed(:country)
  end
end
