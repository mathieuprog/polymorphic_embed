defmodule PolymorphicEmbedTest do
  use ExUnit.Case
  doctest PolymorphicEmbed

  alias PolymorphicEmbed.Repo
  alias PolymorphicEmbed.Reminder
  alias PolymorphicEmbed.Channel.{SMS, Email}
  alias PolymorphicEmbed.Channel.{TwilioSMSProvider}
  alias PolymorphicEmbed.Channel.{SMSResult, SMSAttempts}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "receive embed as map of values" do
    sms_reminder_attrs = %{
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an SMS reminder",
      channel: %{
        __type__: "sms",
        number: "02/807.05.53",
        result: %{success: true},
        attempts: [
          %{
            date: ~U[2020-05-28 07:27:05Z],
            result: %{success: true}
          },
          %{
            date: ~U[2020-05-29 07:27:05Z],
            result: %{success: false}
          },
          %{
            date: ~U[2020-05-30 07:27:05Z],
            result: %{success: true}
          }
        ],
        provider: %{
          __type__: "twilio",
          api_key: "foo"
        }
      }
    }

    insert_result =
      %Reminder{}
      |> Reminder.changeset(sms_reminder_attrs)
      |> Repo.insert()

    assert {:ok, %Reminder{}} = insert_result

    reminder =
      Reminder
      |> QueryBuilder.where(text: "This is an SMS reminder")
      |> Repo.one()

    assert SMS = reminder.channel.__struct__
    assert TwilioSMSProvider = reminder.channel.provider.__struct__
    assert SMSResult == reminder.channel.result.__struct__
    assert true == reminder.channel.result.success
    assert ~U[2020-05-28 07:27:05Z] == hd(reminder.channel.attempts).date
  end

  test "without __type__" do
    attrs = %{
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an Email reminder",
      channel: %{
        address: "john@example.com",
        valid: true,
        confirmed: false
      }
    }

    insert_result =
      %Reminder{}
      |> Reminder.changeset(attrs)
      |> Repo.insert()

    assert {:ok, %Reminder{}} = insert_result

    reminder =
      Reminder
      |> QueryBuilder.where(text: "This is an Email reminder")
      |> Repo.one()

    assert Email = reminder.channel.__struct__
  end

  test "receive embed as struct" do
    reminder =
      %Reminder{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder",
        channel: %SMS{
          provider: %TwilioSMSProvider{
            api_key: "foo"
          },
          number: "02/807.05.53",
          result: %SMSResult{success: true},
          attempts: [
            %SMSAttempts{
              date: ~U[2020-05-28 07:27:05Z],
              result: %SMSResult{success: true}
            },
            %SMSAttempts{
              date: ~U[2020-05-28 07:27:05Z],
              result: %SMSResult{success: true}
            }
          ]
        }
      }

    Repo.insert(reminder)

    reminder =
      Reminder
      |> QueryBuilder.where(text: "This is an SMS reminder")
      |> Repo.one()

    assert SMS = reminder.channel.__struct__
  end
end
