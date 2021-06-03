defmodule PolymorphicEmbed.ExMachinaTest do
  use ExUnit.Case

  import PolymorphicEmbed.Factory

  alias PolymorphicEmbed.Reminder
  alias PolymorphicEmbed.Channel.Email
  alias PolymorphicEmbed.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "inserts reminder" do
    assert %Reminder{channel: %Email{}} = insert(:reminder)
  end
end
