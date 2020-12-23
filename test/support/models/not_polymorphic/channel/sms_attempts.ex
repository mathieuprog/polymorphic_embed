defmodule PolymorphicEmbed.Regular.Channel.SMSAttempts do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field(:date, :utc_datetime)
    embeds_one(:result, PolymorphicEmbed.Regular.Channel.SMSResult)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:date])
    |> cast_embed(:result)
  end
end
