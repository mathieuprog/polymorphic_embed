defmodule PolymorphicEmbed.ChannelData do
  use PolymorphicEmbed, types: [
    sms: PolymorphicEmbed.Channel.SMS,
    email: [module: PolymorphicEmbed.Channel.Email, identify_by_fields: [:address, :confirmed]]
  ]
end
