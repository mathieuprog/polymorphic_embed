defmodule PolymorphicEmbed.Reminder.Context.Device do
  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field :id, :string
    field :type, :string

    embeds_one :extra, Extra do
      field :imei, :string
    end
  end
end
