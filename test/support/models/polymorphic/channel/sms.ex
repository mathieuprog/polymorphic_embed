defmodule PolymorphicEmbed.Channel.SMS do
  use Ecto.Schema
  import Ecto.Changeset
  import PolymorphicEmbed

  embedded_schema do
    field(:number, :string)
    field(:country_code, :integer)

    field(:custom, :boolean, default: false)

    polymorphic_embeds_one(:provider,
      types: [
        twilio: PolymorphicEmbed.Channel.TwilioSMSProvider,
        test: PolymorphicEmbed.Channel.AcmeSMSProvider
      ],
      on_type_not_found: :raise,
      on_replace: :update
    )

    polymorphic_embeds_one(:fallback_provider,
      types: [
        twilio: PolymorphicEmbed.Channel.TwilioSMSProvider,
        test: PolymorphicEmbed.Channel.AcmeSMSProvider
      ],
      on_type_not_found: :nilify,
      on_replace: :update
    )

    embeds_one(:result, PolymorphicEmbed.Channel.SMSResult, on_replace: :update)
    embeds_many(:attempts, PolymorphicEmbed.Channel.SMSAttempts, on_replace: :delete)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:number, :country_code])
    |> cast_embed(:result)
    |> cast_embed(:attempts)
    |> cast_polymorphic_embed(:provider, required: true)
    |> cast_polymorphic_embed(:fallback_provider, required: false)
    |> validate_required([:number, :country_code])
  end

  def custom_changeset(struct, attrs, _foo, _bar) do
    struct
    |> changeset(attrs)
    |> cast(attrs, [:custom])
  end

  def custom_changeset2(struct, attrs) do
    struct
    |> changeset(attrs)
    |> cast(attrs, [:custom])
  end
end
