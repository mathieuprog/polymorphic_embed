defmodule PolymorphicEmbed.Regular.Reminder do
  use Ecto.Schema
  use QueryBuilder
  import Ecto.Changeset
  alias PolymorphicEmbed.Regular.{Todo, Event}

  schema "reminders" do
    field(:date, :utc_datetime)
    field(:text, :string)
    has_one(:todo, Todo)
    belongs_to(:event, Event)

    embeds_one(:channel, PolymorphicEmbed.Regular.Channel.SMS, on_replace: :update)

    embeds_many(:contexts, PolymorphicEmbed.Regular.Reminder.Context.Location, on_replace: :delete)

    timestamps()
  end

  def changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> validate_required(:date)
    |> cast_embed(:channel)
    |> cast_embed(:contexts)
  end

  def custom_changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_embed(:channel,
      with: {PolymorphicEmbed.Regular.Channel.SMS, :custom_changeset, ["foo", "bar"]}
    )
    |> validate_required(:date)
  end

  def custom_changeset2(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_embed(:channel, with: &PolymorphicEmbed.Regular.Channel.SMS.custom_changeset2/2)
    |> validate_required(:date)
  end
end
