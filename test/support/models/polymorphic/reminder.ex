defmodule PolymorphicEmbed.Reminder do
  use Ecto.Schema
  use QueryBuilder
  import Ecto.Changeset
  import PolymorphicEmbed
  alias PolymorphicEmbed.{Todo, Event}

  schema "reminders" do
    field(:date, :utc_datetime)
    field(:text, :string)
    has_one(:todo, Todo)
    belongs_to(:event, Event)

    polymorphic_embeds_one(:channel,
      types: [
        sms: PolymorphicEmbed.Channel.SMS,
        email: [
          module: PolymorphicEmbed.Channel.Email,
          identify_by_fields: [:address, :confirmed]
        ]
      ],
      on_replace: :update,
      type_field_name: :my_type_field,
      retain_unlisted_types_on_load: [:some_deprecated_type]
    )

    polymorphic_embeds_one(:channel2,
      types: [
        sms: PolymorphicEmbed.Channel.SMS,
        email: PolymorphicEmbed.Channel.Email
      ],
      on_replace: :update
    )

    polymorphic_embeds_one(:channel3,
      types: [
        sms: PolymorphicEmbed.Channel.SMS,
        email: PolymorphicEmbed.Channel.Email
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

    polymorphic_embeds_many(:contexts3,
      types: [
        location: PolymorphicEmbed.Reminder.Context.Location,
        age: PolymorphicEmbed.Reminder.Context.Age,
        device: PolymorphicEmbed.Reminder.Context.DeviceNoId
      ],
      on_replace: :delete
    )

    timestamps()
  end

  def changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> validate_required(:date)
    |> cast_polymorphic_embed(:channel)
    |> cast_polymorphic_embed(:channel2)
    |> cast_polymorphic_embed(:channel3)
    |> cast_polymorphic_embed(:contexts,
      sort_param: :contexts_sort,
      default_type_on_sort_create: :location,
      drop_param: :contexts_drop
    )
    |> cast_polymorphic_embed(:contexts2,
      sort_param: :contexts2_sort,
      default_type_on_sort_create: fn -> :location end,
      drop_param: :contexts2_drop
    )
    |> cast_polymorphic_embed(:contexts3)
  end

  def custom_changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_polymorphic_embed(:channel,
      with: [
        sms: &PolymorphicEmbed.Channel.SMS.custom_changeset/2
      ]
    )
    |> validate_required(:date)
  end
end
