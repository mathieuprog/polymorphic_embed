defmodule PolymorphicEmbed.Factory do
  use ExMachina.Ecto, repo: MyApp.Repo

  alias PolymorphicEmbed.{Channel, Reminder}

  def reminder_factory do
    %Reminder{
      text: "Do not forget about this tomorrow",
      date: DateTime.utc_now() |> DateTime.add(60 * 60 * 25, :second),
      channel: build(:channel_sms)
    }
  end

  def channel_sms_factory do
    %Channel.SMS{
      country_code: 1,
      number: "8005551234",
      provider: build(:channel_sms_twillio)
    }
  end

  def channel_sms_twillio_factory do
    %Channel.TwilioSMSProvider{
      api_key: "wRXJehfSOJnUVYe1qTCqQb2JvoO9ekBXvO0Q64lVW8I+mQjkYQyxNSL+4ESEXPR1"
    }
  end
end
