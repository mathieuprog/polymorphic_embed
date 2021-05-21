defmodule PolymorphicEmbed.Regular.Channel.SMSResult do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field(:success, :boolean)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:success])
    |> validate_required([:success])
  end
end
