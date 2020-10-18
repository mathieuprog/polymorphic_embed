defmodule PolymorphicEmbed.Reminder do
  use Ecto.Schema
  use QueryBuilder
  import Ecto.Changeset
  import PolymorphicEmbed, only: [cast_polymorphic_embed: 2]

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
      ]
    )

    timestamps()
  end

  def changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_polymorphic_embed(:channel)
    |> validate_required(:date)
  end
end
