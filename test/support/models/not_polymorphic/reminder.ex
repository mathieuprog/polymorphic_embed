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

    embeds_many(:contexts, PolymorphicEmbed.Regular.Reminder.Context.Location,
      on_replace: :delete
    )

    embeds_many(:contexts3, PolymorphicEmbed.Regular.Reminder.Context.DeviceNoId,
      on_replace: :delete
    )

    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:date, :text])
    |> validate_required(:date)
    |> cast_embed(:channel)
    |> cast_embed(:contexts,
      sort_param: :contexts_sort,
      drop_param: :contexts_drop
    )
    |> cast_embed(:contexts3)
  end

  def custom_changeset(struct, attrs) do
    struct
    |> cast(attrs, [:date, :text])
    |> cast_embed(:channel, with: &PolymorphicEmbed.Regular.Channel.SMS.custom_changeset/2)
    |> validate_required(:date)
  end
end
