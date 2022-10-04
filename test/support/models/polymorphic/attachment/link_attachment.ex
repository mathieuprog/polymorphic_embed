defmodule PolymorphicEmbed.Attachment.LinkAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :url, :string
    field :title, :string
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:url, :title])
  end
end
