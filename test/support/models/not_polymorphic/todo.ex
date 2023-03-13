defmodule PolymorphicEmbed.Regular.Todo do
  @moduledoc """
  A todo item, which always has a single reminder.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias PolymorphicEmbed.Regular.Reminder

  schema "todos" do
    belongs_to(:reminder, Reminder)
    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [])
    |> cast_assoc(:reminder, required: true)
  end
end
