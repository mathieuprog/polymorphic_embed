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

    field(:source, PolymorphicEmbed, types: :by_module)
    field(:reference, PolymorphicEmbed, types: &__MODULE__.lookup_type/2)

    timestamps()
  end

  def changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_polymorphic_embed(:channel)
    |> cast_polymorphic_embed(:source)
    |> validate_required(:date)
  end

  def lookup_type(key, :module) do
    %{sms: PolymorphicEmbed.Channel.SMS, email: PolymorphicEmbed.Channel.Email}
    |> Map.fetch!(key)
  end

  def lookup_type(key, :type) do
    %{PolymorphicEmbed.Channel.SMS => :sms, PolymorphicEmbed.Channel.Email => :email}
    |> Map.fetch!(key)
  end
end
