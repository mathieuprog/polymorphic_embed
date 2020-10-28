{:ok, _} = PolymorphicEmbed.Repo.start_link()

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(PolymorphicEmbed.Repo, :manual)
