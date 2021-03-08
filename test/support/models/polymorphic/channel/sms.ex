defmodule PolymorphicEmbed.Channel.SMS do
  use Ecto.Schema
  import Ecto.Changeset
  import PolymorphicEmbed, only: [cast_polymorphic_embed: 3]

  @primary_key false

  embedded_schema do
    field(:number, :string)
    field(:country_code, :integer)

    field(:custom, :boolean, default: false)

    field(:provider, PolymorphicEmbed,
      types: [
        twilio: PolymorphicEmbed.Channel.TwilioSMSProvider,
        test: PolymorphicEmbed.Channel.AcmeSMSProvider
      ],
      on_type_not_found: :raise,
      on_replace: :update
    )

    embeds_one(:result, PolymorphicEmbed.Channel.SMSResult)
    embeds_many(:attempts, PolymorphicEmbed.Channel.SMSAttempts)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:number, :country_code])
    |> cast_embed(:result)
    |> cast_embed(:attempts)
    |> cast_polymorphic_embed(:provider, required: true)
    |> validate_required([:number, :country_code])
  end

  def custom_changeset(struct, attrs) do
    struct
    |> changeset(attrs)
    |> cast(attrs, [:custom])
  end
end
