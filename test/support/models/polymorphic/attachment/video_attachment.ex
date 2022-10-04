defmodule PolymorphicEmbed.Attachment.VideoAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :url, :string
    field :thumbnail_url, :string
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:url, :thumbnail_url])
    |> validate_required([:url])
  end
end
