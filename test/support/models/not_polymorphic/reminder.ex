defmodule PolymorphicEmbed.Regular.Reminder do
  use Ecto.Schema
  use QueryBuilder
  import Ecto.Changeset

  schema "reminders" do
    field(:date, :utc_datetime)
    field(:text, :string)

    embeds_one(:channel, PolymorphicEmbed.Regular.Channel.SMS, on_replace: :update)

    embeds_many(:contexts, PolymorphicEmbed.Regular.Reminder.Context.Location, on_replace: :delete)

    timestamps()
  end

  def changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_embed(:channel)
    |> cast_embed(:contexts)
    |> validate_required(:date)
  end

  def custom_changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_embed(:channel, with: {PolymorphicEmbed.Regular.Channel.SMS, :custom_changeset, ["foo", "bar"]})
    |> validate_required(:date)
  end

  def custom_changeset2(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_embed(:channel, with: &PolymorphicEmbed.Regular.Channel.SMS.custom_changeset2/2)
    |> validate_required(:date)
  end
end
