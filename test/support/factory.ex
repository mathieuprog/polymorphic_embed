defmodule PolymorphicEmbed.Factory do
  use PolymorphicEmbed.ExMachina.Ecto, repo: PolymorphicEmbed.Repo

  alias PolymorphicEmbed.Reminder
  alias PolymorphicEmbed.Channel.Email

  def reminder_factory do
    %Reminder{
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an Email reminder",
      channel: %Email{
        address: "john@example.com",
        valid: true,
        confirmed: false
      }
    }
  end
end
