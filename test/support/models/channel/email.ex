defmodule PolymorphicEmbed.Channel.Email do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field(:address, :string)
    field(:confirmed, :boolean)
    field(:valid, :boolean)
  end

  def changeset(email, params) do
    email
    |> cast(params, ~w(address confirmed valid)a)
    |> validate_required(:address)
    |> validate_length(:address, min: 3)
  end
end
