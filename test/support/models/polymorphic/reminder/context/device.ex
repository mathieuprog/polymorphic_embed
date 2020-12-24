defmodule PolymorphicEmbed.Reminder.Context.Device do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :id, :string
    field :type, :string

    embeds_one :extra, Extra do
      field :imei, :string
    end
  end

  def changeset(struct, params) do
    struct
    |> cast(params, ~w(id type)a)
    |> validate_required(~w(type)a)
  end
end
