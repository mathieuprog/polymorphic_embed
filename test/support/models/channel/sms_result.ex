defmodule PolymorphicEmbed.Channel.SMSResult do
  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field(:success, :boolean)
  end
end
