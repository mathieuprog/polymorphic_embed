defmodule PolymorphicEmbed.Country do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :name, :string
    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, ~w(name)a)
    |> validate_required(~w(name)a)
    |> validate_length(:name, min: 3)
  end
end
