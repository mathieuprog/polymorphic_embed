use Mix.Config

config :logger, level: :warn

config :polymorphic_embed,
  ecto_repos: [PolymorphicEmbed.Repo]

config :polymorphic_embed, PolymorphicEmbed.Repo,
  username: "postgres",
  password: "postgres",
  database: "polymorphic_embed",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support"
