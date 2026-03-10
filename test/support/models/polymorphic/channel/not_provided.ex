defmodule PolymorphicEmbed.Channel.NotProvided do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
  end

  def changeset(struct, attrs) do
    cast(struct, attrs, [])
  end
end
