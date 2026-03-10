defmodule PolymorphicEmbed.Reminder.Context.Extra do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :imei, :string
  end

  def changeset(extra, attrs) do
    extra
    |> cast(attrs, [:imei])
    |> validate_required([:imei])
  end
end
