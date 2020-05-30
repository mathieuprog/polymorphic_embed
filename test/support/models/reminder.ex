defmodule PolymorphicEmbed.Reminder do
  use Ecto.Schema
  use QueryBuilder
  import Ecto.Changeset

  schema "reminders" do
    field(:date, :utc_datetime)
    field(:text, :string)
    field(:channel, PolymorphicEmbed.ChannelData)

    timestamps()
  end

  def changeset(struct, values) do
    struct
    |> cast(values, [:date, :text, :channel])
    |> validate_required(:date)
  end
end
