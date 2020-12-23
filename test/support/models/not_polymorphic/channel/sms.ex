defmodule PolymorphicEmbed.Regular.Channel.SMS do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field(:number, :string)
    field(:country_code, :integer)

    embeds_one(:provider, PolymorphicEmbed.Regular.Channel.TwilioSMSProvider)

    embeds_one(:result, PolymorphicEmbed.Regular.Channel.SMSResult)
    embeds_many(:attempts, PolymorphicEmbed.Regular.Channel.SMSAttempts)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:number, :country_code])
    |> cast_embed(:result)
    |> cast_embed(:attempts)
    |> cast_embed(:provider)
    |> validate_required([:number, :country_code])
  end
end
