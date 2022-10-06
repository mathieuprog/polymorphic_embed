defmodule PolymorphicEmbed.Attachment.VideoAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :url, :string
    field :thumbnail_url, :string
    field :custom, :boolean, default: false
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:url, :thumbnail_url])
    |> validate_required([:url])
  end

  def custom_changeset(struct, attrs, _foo, _bar) do
    struct
    |> changeset(attrs)
    |> cast(attrs, [:custom])
  end

  def custom_changeset2(struct, attrs) do
    struct
    |> changeset(attrs)
    |> cast(attrs, [:custom])
  end
end
