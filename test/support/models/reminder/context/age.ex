defmodule PolymorphicEmbed.Reminder.Context.Age do
  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field :age, :string
  end
end
