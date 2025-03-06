defmodule PolymorphicEmbed.Reminder.Context.Device do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :ref, :string
    field :type, :string

    embeds_one :extra, PolymorphicEmbed.Reminder.Context.Extra
  end

  def changeset(struct, params) do
    struct
    |> cast(params, ~w(ref type)a)
    |> validate_required(~w(type)a)
    |> cast_embed(:extra)
  end
end
