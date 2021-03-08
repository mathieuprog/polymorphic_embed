defmodule PolymorphicEmbed.Reminder do
  use Ecto.Schema
  use QueryBuilder
  import Ecto.Changeset
  import PolymorphicEmbed, only: [cast_polymorphic_embed: 2, cast_polymorphic_embed: 3]

  schema "reminders" do
    field(:date, :utc_datetime)
    field(:text, :string)

    field(:channel, PolymorphicEmbed,
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

    field(:contexts, {:array, PolymorphicEmbed},
      types: [
        location: PolymorphicEmbed.Reminder.Context.Location,
        age: PolymorphicEmbed.Reminder.Context.Age,
        device: PolymorphicEmbed.Reminder.Context.Device
      ],
      on_replace: :delete
    )

    timestamps()
  end

  def changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_polymorphic_embed(:channel)
    |> cast_polymorphic_embed(:contexts)
    |> validate_required(:date)
  end

  def custom_changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_polymorphic_embed(:channel, with: :custom_changeset)
    |> validate_required(:date)
  end
end
