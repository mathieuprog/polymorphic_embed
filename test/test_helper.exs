{:ok, _} = PolymorphicEmbed.Repo.start_link()
{:ok, _} = Application.ensure_all_started(:ex_machina)

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(PolymorphicEmbed.Repo, :manual)
