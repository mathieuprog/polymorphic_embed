defmodule PolymorphicEmbed.Reminder do
  use Ecto.Schema
  use QueryBuilder
  import Ecto.Changeset
  import PolymorphicEmbed

  schema "reminders" do
    field(:date, :utc_datetime)
    field(:text, :string)

    polymorphic_embeds_one(:channel,
      types: [
        sms: PolymorphicEmbed.Channel.SMS,
        email: [
          module: PolymorphicEmbed.Channel.Email,
          identify_by_fields: [:address, :confirmed]
        ]
      ],
      on_replace: :update,
      type_field: :my_type_field
    )

    polymorphic_embeds_many(:contexts,
      types: [
        location: PolymorphicEmbed.Reminder.Context.Location,
        age: PolymorphicEmbed.Reminder.Context.Age,
        device: PolymorphicEmbed.Reminder.Context.Device
      ],
      on_replace: :delete
    )

    polymorphic_embeds_many(:contexts2,
      types: [
        location: PolymorphicEmbed.Reminder.Context.Location,
        age: PolymorphicEmbed.Reminder.Context.Age,
        device: PolymorphicEmbed.Reminder.Context.Device
      ],
      on_type_not_found: :ignore,
      on_replace: :delete
    )

    polymorphic_embeds_one(:attachment, types: :by_module, on_replace: :update)

    timestamps()
  end

  def changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> validate_required(:date)
    |> cast_polymorphic_embed(:channel)
    |> cast_polymorphic_embed(:attachment)
    |> cast_polymorphic_embed(:contexts)
    |> cast_polymorphic_embed(:contexts2)
  end

  def custom_changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_polymorphic_embed(:channel,
      with: [
        sms: {PolymorphicEmbed.Channel.SMS, :custom_changeset, ["foo", "bar"]},
        email: {PolymorphicEmbed.Channel.Email, :custom_changeset, ["foo", "bar"]}
      ]
    )
    |> cast_polymorphic_embed(:attachment,
      with: {PolymorphicEmbed.Attachment.VideoAttachment, :custom_changeset, ["foo", "bar"]}
    )
    |> validate_required(:date)
  end

  def custom_changeset2(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_polymorphic_embed(:channel,
      with: [
        sms: &PolymorphicEmbed.Channel.SMS.custom_changeset2/2
      ]
    )
    |> cast_polymorphic_embed(:attachment,
      with: &PolymorphicEmbed.Attachment.VideoAttachment.custom_changeset2/2
    )
    |> validate_required(:date)
  end

  # def custom_changeset3(struct, values) do
  #   struct
  #   |> cast(values, [:date, :text])
  #   |> cast_polymorphic_embed(:channel,
  #     with: [
  #       sms: &PolymorphicEmbed.Channel.SMS.custom_changeset2/2
  #     ]
  #   )
  #   |> validate_required(:date)
  # end
end
