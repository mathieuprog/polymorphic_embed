defmodule PolymorphicEmbed.Reminder.Context.Age do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :age, :string
  end

  def changeset(struct, params) do
    struct
    |> cast(params, ~w(age)a)
  end
end
