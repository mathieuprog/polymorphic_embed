defmodule PolymorphicEmbed.Regular.Channel.TwilioSMSProvider do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field(:api_key, :string)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:api_key])
  end
end
