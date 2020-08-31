defmodule PolymorphicEmbedTest do
  use ExUnit.Case
  doctest PolymorphicEmbed

  import Phoenix.HTML
  import Phoenix.HTML.Form
  import PolymorphicEmbed.HTML.Form

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
    reminder = %Reminder{
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

  test "inputs_for/4" do
    attrs = %{
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an Email reminder",
      channel: %{
        address: "a",
        valid: true,
        confirmed: true
      }
    }

    changeset =
      %Reminder{}
      |> Reminder.changeset(attrs)

    contents =
      safe_inputs_for(changeset, :channel, :email, fn f ->
        assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
        assert f.errors == []
        text_input(f, :address)
      end)

    assert contents ==
             ~s(<input id="reminder_channel___type__" name="reminder[channel][__type__]" type="hidden" value="email"><input id="reminder_channel_address" name="reminder[channel][address]" type="text">)

    contents =
      safe_inputs_for(Map.put(changeset, :action, :insert), :channel, :email, fn f ->
        assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
        refute f.errors == []
        text_input(f, :address)
      end)

    assert contents ==
             ~s(<input id="reminder_channel___type__" name="reminder[channel][__type__]" type="hidden" value="email"><input id="reminder_channel_address" name="reminder[channel][address]" type="text">)
  end

  describe "get_polymorphic_type/1" do
    test "returns the type for a module" do
      assert PolymorphicEmbed.ChannelData.get_polymorphic_type(SMS) == :sms
    end

    test "returns the type for a struct" do
      assert PolymorphicEmbed.ChannelData.get_polymorphic_type(%Email{
               address: "what",
               confirmed: true
             }) ==
               :email
    end
  end

  defp safe_inputs_for(changeset, field, type, fun) do
    mark = "--PLACEHOLDER--"

    contents =
      safe_to_string(
        form_for(changeset, "/", fn f ->
          html_escape([mark, polymorphic_embed_inputs_for(f, field, type, fun), mark])
        end)
      )

    [_, inner, _] = String.split(contents, mark)
    inner
  end
end
