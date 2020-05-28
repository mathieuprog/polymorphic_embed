defmodule PolymorphicEmbed.Repo do
  use Ecto.Repo,
    otp_app: :polymorphic_embed,
    adapter: Ecto.Adapters.Postgres
end
