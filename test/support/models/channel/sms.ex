defmodule PolymorphicEmbed.Channel.SMS do
  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field(:number, :string)

    field(:provider, PolymorphicEmbed,
      types: [
        twilio: PolymorphicEmbed.Channel.TwilioSMSProvider,
        test: PolymorphicEmbed.Channel.AcmeSMSProvider
      ]
    )

    embeds_one(:result, PolymorphicEmbed.Channel.SMSResult)
    embeds_many(:attempts, PolymorphicEmbed.Channel.SMSAttempts)
  end
end
