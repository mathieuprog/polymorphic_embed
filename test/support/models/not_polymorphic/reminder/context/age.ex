defmodule PolymorphicEmbed.Regular.Reminder.Context.Age do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :age, :string
  end

  def changeset(struct, params) do
    struct
    |> cast(params, ~w(age)a)
  end
end
