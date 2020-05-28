defmodule PolymorphicEmbed.Channel.SMSProvider do
  use PolymorphicEmbed, types: [
    twilio: PolymorphicEmbed.Channel.TwilioSMSProvider,
    test: PolymorphicEmbed.Channel.AcmeSMSProvider,
  ]
end
