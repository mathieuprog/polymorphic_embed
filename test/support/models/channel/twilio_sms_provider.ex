defmodule PolymorphicEmbed.Channel.TwilioSMSProvider do
  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field :api_key, :string
  end
end
