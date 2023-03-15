defmodule PolymorphicEmbed.Regular.Todo do
  @moduledoc """
  A todo item, which can optionally have a single reminder.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias PolymorphicEmbed.Regular.Reminder

  schema "todos" do
    belongs_to(:reminder, Reminder)
    embeds_one(:embedded_reminder, Reminder)
    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [])
    |> cast_assoc(:reminder)
    |> cast_embed(:embedded_reminder)
  end
end
