defmodule PolymorphicEmbed.Event do
  @moduledoc """
  An (calendar) event, which can optionally have multiple reminders.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias PolymorphicEmbed.Reminder

  schema "events" do
    has_many(:reminders, Reminder)
    embeds_many(:embedded_reminders, Reminder)
    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [])
    |> cast_assoc(:reminders)
    |> cast_embed(:embedded_reminders)
  end
end
