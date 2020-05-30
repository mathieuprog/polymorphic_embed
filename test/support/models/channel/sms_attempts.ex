defmodule PolymorphicEmbed.Channel.SMSAttempts do
  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field(:date, :utc_datetime)
    embeds_one(:result, PolymorphicEmbed.Channel.SMSResult)
  end
end
