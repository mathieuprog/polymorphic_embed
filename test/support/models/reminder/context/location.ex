defmodule PolymorphicEmbed.Reminder.Context.Location do
  use Ecto.Schema

  @primary_key false

  embedded_schema do
    belongs_to :country, PolymorphicEmbed.Country
    field :address, :string
  end
end
