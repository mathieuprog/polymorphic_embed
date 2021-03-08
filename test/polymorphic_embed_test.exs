defmodule PolymorphicEmbedTest do
  use ExUnit.Case
  doctest PolymorphicEmbed

  import Phoenix.HTML
  import Phoenix.HTML.Form
  import PolymorphicEmbed.HTML.Form

  alias PolymorphicEmbed.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp get_module(name, true = _polymorphic?), do: Module.concat([PolymorphicEmbed, name])

  defp get_module(name, false = _polymorphic?),
    do: Module.concat([PolymorphicEmbed.Regular, name])

  test "receive embed as map of values" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)

      sms_reminder_attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder #{polymorphic?}",
        channel: %{
          my_type_field: "sms",
          number: "02/807.05.53",
          country_code: 1,
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
        struct(reminder_module)
        |> reminder_module.changeset(sms_reminder_attrs)
        |> Repo.insert()

      assert {:ok, %reminder_module{}} = insert_result

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an SMS reminder #{polymorphic?}")
        |> Repo.one()

      assert get_module(Channel.SMS, polymorphic?) == reminder.channel.__struct__

      assert get_module(Channel.TwilioSMSProvider, polymorphic?) ==
               reminder.channel.provider.__struct__

      assert get_module(Channel.SMSResult, polymorphic?) == reminder.channel.result.__struct__
      assert true == reminder.channel.result.success
      assert ~U[2020-05-28 07:27:05Z] == hd(reminder.channel.attempts).date
    end
  end

  test "invalid values" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)

      sms_reminder_attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder",
        channel: %{
          my_type_field: "sms"
        }
      }

      insert_result =
        struct(reminder_module)
        |> reminder_module.changeset(sms_reminder_attrs)
        |> Repo.insert()

      assert {:error,
              %Ecto.Changeset{
                action: :insert,
                valid?: false,
                errors: errors,
                changes: %{
                  channel: %{
                    action: :insert,
                    valid?: false,
                    errors: channel_errors
                  }
                }
              }} = insert_result

      assert [] = errors

      assert %{
               number: {"can't be blank", [validation: :required]},
               country_code: {"can't be blank", [validation: :required]},
               provider: {"can't be blank", [validation: :required]}
             } = Map.new(channel_errors)
    end
  end

  test "receive embed as struct" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)
      sms_module = get_module(Channel.SMS, polymorphic?)
      sms_provider_module = get_module(Channel.TwilioSMSProvider, polymorphic?)
      sms_result_module = get_module(Channel.SMSResult, polymorphic?)
      sms_attempts_module = get_module(Channel.SMSAttempts, polymorphic?)

      reminder =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an SMS reminder #{polymorphic?}",
          channel:
            struct(sms_module,
              provider:
                struct(sms_provider_module,
                  api_key: "foo"
                ),
              country_code: 1,
              number: "02/807.05.53",
              result: struct(sms_result_module, success: true),
              attempts: [
                struct(sms_attempts_module,
                  date: ~U[2020-05-28 07:27:05Z],
                  result: struct(sms_result_module, success: true)
                ),
                struct(sms_attempts_module,
                  date: ~U[2020-05-28 07:27:05Z],
                  result: struct(sms_result_module, success: true)
                )
              ]
            )
        )

      reminder
      |> reminder_module.changeset(%{})
      |> Repo.insert()

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an SMS reminder #{polymorphic?}")
        |> Repo.one()

      assert sms_module == reminder.channel.__struct__

      changeset =
        reminder
        |> reminder_module.changeset(%{channel: %{provider: nil}})

      assert %Ecto.Changeset{
               action: nil,
               valid?: false,
               errors: [],
               changes: %{
                 channel: %{
                   action: :update,
                   valid?: false,
                   errors: [provider: {"can't be blank", [validation: :required]}]
                 }
               }
             } = changeset

      insert_result =
        changeset
        |> Repo.insert()

      assert {:error,
              %Ecto.Changeset{
                action: :insert,
                valid?: false,
                errors: errors,
                changes: %{
                  channel: %{
                    action: :update,
                    valid?: false,
                    errors: channel_errors
                  }
                }
              }} = insert_result

      assert [] = errors
      assert %{provider: {"can't be blank", [validation: :required]}} = Map.new(channel_errors)
    end
  end

  test "without __type__" do
    reminder_module = get_module(Reminder, true)
    email_module = get_module(Channel.Email, true)

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
      struct(reminder_module)
      |> reminder_module.changeset(attrs)
      |> Repo.insert()

    assert {:ok, %reminder_module{}} = insert_result

    reminder =
      reminder_module
      |> QueryBuilder.where(text: "This is an Email reminder")
      |> Repo.one()

    assert email_module == reminder.channel.__struct__
  end

  test "loading a nil embed" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)

      insert_result =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an Email reminder #{polymorphic?}",
          channel: nil
        )
        |> Repo.insert()

      assert {:ok, %reminder_module{}} = insert_result

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an Email reminder #{polymorphic?}")
        |> Repo.one()

      assert is_nil(reminder.channel)
    end
  end

  test "casting a nil embed" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)

      attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an Email reminder #{polymorphic?}",
        channel: nil
      }

      insert_result =
        struct(reminder_module)
        |> reminder_module.changeset(attrs)
        |> Repo.insert()

      assert {:ok, %reminder_module{}} = insert_result

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an Email reminder #{polymorphic?}")
        |> Repo.one()

      assert is_nil(reminder.channel)
    end
  end

  test "required true" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)

      sms_reminder_attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder #{polymorphic?}",
        channel: %{
          my_type_field: "sms",
          number: "02/807.05.53",
          country_code: 1,
          attempts: [],
          provider: nil
        }
      }

      insert_result =
        struct(reminder_module)
        |> reminder_module.changeset(sms_reminder_attrs)
        |> Repo.insert()

      assert {:error,
              %{
                valid?: false,
                changes: %{
                  channel: %{
                    valid?: false,
                    errors: [provider: {"can't be blank", [validation: :required]}]
                  }
                }
              }} = insert_result
    end
  end

  test "custom_changeset" do
    reminder_module = get_module(Reminder, true)
    sms_provider_module = get_module(Channel.TwilioSMSProvider, true)

    sms_reminder_attrs = %{
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an SMS reminder true",
      channel: %{
        my_type_field: "sms",
        number: "02/807.05.53",
        country_code: 1,
        attempts: [],
        provider: %{__type__: "twilio", api_key: "somekey"},
        custom: true
      }
    }

    insert_result =
      struct(reminder_module)
      |> reminder_module.custom_changeset(sms_reminder_attrs)
      |> Repo.insert()

    assert {:ok, %reminder_module{} = reminder} = insert_result
    assert reminder.channel.custom
  end

  test "setting embed to nil" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)
      sms_module = get_module(Channel.SMS, polymorphic?)

      attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder #{polymorphic?}",
        channel: nil
      }

      insert_result =
        struct(reminder_module,
          channel:
            struct(sms_module,
              number: "02/807.05.53",
              country_code: 32
            )
        )
        |> reminder_module.changeset(attrs)
        |> Repo.insert()

      assert {:ok, %reminder_module{}} = insert_result

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an SMS reminder #{polymorphic?}")
        |> Repo.one()

      assert is_nil(reminder.channel)
    end
  end

  test "omitting embed field in cast" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)
      sms_module = get_module(Channel.SMS, polymorphic?)

      attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an Email reminder #{polymorphic?}"
      }

      insert_result =
        struct(reminder_module,
          channel:
            struct(sms_module,
              number: "02/807.05.53"
            )
        )
        |> reminder_module.changeset(attrs)
        |> Repo.insert()

      assert {:ok, %reminder_module{}} = insert_result

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an Email reminder #{polymorphic?}")
        |> Repo.one()

      refute is_nil(reminder.channel)
    end
  end

  test "keep existing data" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)
      sms_module = get_module(Channel.SMS, polymorphic?)
      sms_provider_module = get_module(Channel.TwilioSMSProvider, polymorphic?)
      sms_result_module = get_module(Channel.SMSResult, polymorphic?)
      sms_attempts_module = get_module(Channel.SMSAttempts, polymorphic?)

      struct(reminder_module, channel: struct(sms_module, country_code: 1))

      reminder =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an SMS reminder #{polymorphic?}",
          channel:
            struct(sms_module,
              provider:
                struct(sms_provider_module,
                  api_key: "foo"
                ),
              number: "02/807.05.53",
              country_code: 32,
              result: struct(sms_result_module, success: true),
              attempts: [
                struct(sms_attempts_module,
                  date: ~U[2020-05-28 07:27:05Z],
                  result: struct(sms_result_module, success: true)
                ),
                struct(sms_attempts_module,
                  date: ~U[2020-05-28 07:27:05Z],
                  result: struct(sms_result_module, success: true)
                )
              ]
            )
        )

      reminder = reminder |> Repo.insert!()

      changeset =
        reminder
        |> reminder_module.changeset(%{
          channel: %{
            number: "54"
          }
        })

      changeset |> Repo.update!()

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an SMS reminder #{polymorphic?}")
        |> Repo.one()

      assert reminder.channel.result.success
    end
  end

  test "params with string keys" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)
      sms_module = get_module(Channel.SMS, polymorphic?)
      sms_provider_module = get_module(Channel.TwilioSMSProvider, polymorphic?)
      sms_result_module = get_module(Channel.SMSResult, polymorphic?)
      sms_attempts_module = get_module(Channel.SMSAttempts, polymorphic?)

      reminder =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an SMS reminder #{polymorphic?}",
          channel:
            struct(sms_module,
              provider:
                struct(sms_provider_module,
                  api_key: "foo"
                ),
              number: "02/807.05.53",
              country_code: 32,
              result: struct(sms_result_module, success: true),
              attempts: [
                struct(sms_attempts_module,
                  date: ~U[2020-05-28 07:27:05Z],
                  result: struct(sms_result_module, success: true)
                ),
                struct(sms_attempts_module,
                  date: ~U[2020-05-28 07:27:05Z],
                  result: struct(sms_result_module, success: true)
                )
              ]
            )
        )

      reminder = reminder |> Repo.insert!()

      changeset =
        reminder
        |> reminder_module.changeset(%{
          "channel" => %{
            "my_type_field" => "sms",
            "number" => "54"
          }
        })

      changeset |> Repo.update!()

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an SMS reminder #{polymorphic?}")
        |> Repo.one()

      assert reminder.channel.result.success
    end
  end

  test "missing __type__ leads to changeset error" do
    reminder_module = get_module(Reminder, true)

    sms_reminder_attrs = %{
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an SMS reminder",
      channel: %{
        number: "02/807.05.53",
        country_code: 1,
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
      struct(reminder_module)
      |> reminder_module.changeset(sms_reminder_attrs)
      |> Repo.insert()

    assert {:error, %Ecto.Changeset{errors: [channel: {"is invalid", []}]}} = insert_result
  end

  test "missing __type__ leads to raising error" do
    reminder_module = get_module(Reminder, true)

    sms_reminder_attrs = %{
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an SMS reminder",
      channel: %{
        my_type_field: "sms",
        number: "02/807.05.53",
        country_code: 1,
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
          api_key: "foo"
        }
      }
    }

    assert_raise RuntimeError, ~r"could not infer polymorphic embed from data", fn ->
      struct(reminder_module)
      |> reminder_module.changeset(sms_reminder_attrs)
      |> Repo.insert()
    end
  end

  test "cannot load the right struct" do
    reminder_module = get_module(Reminder, true)
    sms_module = get_module(Channel.SMS, true)

    struct(reminder_module,
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an SMS reminder",
      channel:
        struct(sms_module,
          country_code: 1,
          number: "02/807.05.53"
        )
    )
    |> Repo.insert()

    Ecto.Adapters.SQL.query!(
      Repo,
      "UPDATE reminders SET channel = jsonb_set(channel, '{my_type_field}', '\"foo\"')",
      []
    )

    assert_raise RuntimeError, ~r"could not infer polymorphic embed from data .* \"foo\"", fn ->
      reminder_module
      |> QueryBuilder.where(text: "This is an SMS reminder")
      |> Repo.one()
    end
  end

  test "changing type" do
    reminder_module = get_module(Reminder, true)
    sms_module = get_module(Channel.SMS, true)

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
      struct(reminder_module)
      |> reminder_module.changeset(attrs)
      |> Repo.insert()

    assert {:ok, %reminder_module{} = reminder} = insert_result

    update_attrs = %{
      date: ~U[2020-05-29 02:57:19Z],
      text: "This is an SMS reminder",
      channel: %{
        my_type_field: "sms",
        number: "02/807.05.53",
        country_code: 1,
        attempts: [],
        provider: %{
          __type__: "twilio",
          api_key: "foo"
        }
      }
    }

    update_result =
      reminder
      |> reminder_module.changeset(update_attrs)
      |> Repo.update()

    assert {:ok, %reminder_module{} = updated_reminder} = update_result

    reminder =
      reminder_module
      |> QueryBuilder.where(text: "This is an SMS reminder")
      |> Repo.one()

    assert sms_module == reminder.channel.__struct__
  end

  test "supports lists of polymorphic embeds" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)
      device_module = get_module(Reminder.Context.Device, polymorphic?)
      age_module = get_module(Reminder.Context.Age, polymorphic?)
      location_module = get_module(Reminder.Context.Location, polymorphic?)

      attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is a reminder with multiple contexts #{polymorphic?}",
        channel: %{
          my_type_field: "sms",
          number: "02/807.05.53",
          country_code: 1,
          provider: %{
            __type__: "twilio",
            api_key: "foo"
          }
        },
        contexts: [
          %{
            __type__: "device",
            id: "12345",
            type: "cellphone",
            address: "address"
          },
          %{
            __type__: "age",
            age: "aquarius",
            address: "address"
          }
        ]
      }

      struct(reminder_module)
      |> reminder_module.changeset(attrs)
      |> Repo.insert!()

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is a reminder with multiple contexts #{polymorphic?}")
        |> Repo.one()

      assert reminder.contexts |> length() == 2

      if polymorphic? do
        assert [
                 struct(device_module,
                   id: "12345",
                   type: "cellphone"
                 ),
                 struct(age_module,
                   age: "aquarius"
                 )
               ] == reminder.contexts
      else
        assert [
                 struct(location_module, address: "address"),
                 struct(location_module, address: "address")
               ] == reminder.contexts
      end
    end
  end

  test "validates lists of polymorphic embeds" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)

      attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is a reminder with multiple contexts",
        contexts: [
          %{
            id: "12345",
            type: "cellphone"
          },
          %{
            age: "aquarius"
          }
        ]
      }

      insert_result =
        struct(reminder_module)
        |> reminder_module.changeset(attrs)
        |> Repo.insert()

      if polymorphic? do
        assert {:error, %Ecto.Changeset{valid?: false, errors: [contexts: {"is invalid", _}]}} =
                 insert_result
      else
        assert {:error,
                %Ecto.Changeset{
                  valid?: false,
                  errors: errors,
                  changes: %{contexts: [%{errors: location_errors} | _]}
                }} = insert_result

        assert [] = errors
        assert %{address: {"can't be blank", [validation: :required]}} = Map.new(location_errors)
      end

      if polymorphic? do
        attrs = %{
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is a reminder with multiple contexts",
          contexts: [
            %{
              __type__: "device",
              id: "12345"
            },
            %{
              __type__: "age",
              age: "aquarius"
            }
          ]
        }

        insert_result =
          struct(reminder_module)
          |> reminder_module.changeset(attrs)
          |> Repo.insert()

        assert {:error,
                %Ecto.Changeset{
                  valid?: false,
                  action: :insert,
                  errors: errors,
                  changes: %{contexts: [%{errors: device_errors, action: :insert} | _]}
                }} = insert_result

        assert [] = errors
        assert %{type: {"can't be blank", [validation: :required]}} = Map.new(device_errors)

        device_module = get_module(Reminder.Context.Device, true)

        reminder =
          struct(reminder_module,
            date: ~U[2020-05-28 02:57:19Z],
            text: "This is an SMS reminder #{polymorphic?}",
            constexts: [
              struct(device_module, id: "12345")
            ]
          )

        attrs = %{
          contexts: [
            %{
              __type__: "device",
              id: "54321"
            },
            %{
              __type__: "age",
              age: "aquarius"
            }
          ]
        }

        insert_result =
          reminder
          |> reminder_module.changeset(attrs)
          |> Repo.insert()

        assert {:error,
                %Ecto.Changeset{
                  valid?: false,
                  action: :insert,
                  errors: errors,
                  changes: %{contexts: [%{errors: device_errors, action: :insert} | _]}
                }} = insert_result

        assert [] = errors
        assert %{type: {"can't be blank", [validation: :required]}} = Map.new(device_errors)
      end
    end
  end

  test "inputs_for/4" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)

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
        struct(reminder_module)
        |> reminder_module.changeset(attrs)

      contents =
        safe_inputs_for(changeset, :channel, :email, polymorphic?, fn f ->
          assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
          assert f.errors == []
          text_input(f, :address)
        end)

      expected_contents =
        if(polymorphic?,
          do:
            ~s(<input id="reminder_channel___type__" name="reminder[channel][__type__]" type="hidden" value="email"><input id="reminder_channel_address" name="reminder[channel][address]" type="text" value="a">),
          else:
            ~s(<input id="reminder_channel_address" name="reminder[channel][address]" type="text" value="a">)
        )

      assert contents == expected_contents

      contents =
        safe_inputs_for(
          Map.put(changeset, :action, :insert),
          :channel,
          :email,
          polymorphic?,
          fn f ->
            assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
            text_input(f, :address)
          end
        )

      expected_contents =
        if(polymorphic?,
          do:
            ~s(<input id="reminder_channel___type__" name="reminder[channel][__type__]" type="hidden" value="email"><input id="reminder_channel_address" name="reminder[channel][address]" type="text" value="a">),
          else:
            ~s(<input id="reminder_channel_address" name="reminder[channel][address]" type="text" value="a">)
        )

      assert contents == expected_contents
    end
  end

  test "inputs_for/4 after invalid insert" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)

      attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder",
        channel: %{
          my_type_field: "sms",
          number: "1"
        }
      }

      {:error, changeset} =
        struct(reminder_module)
        |> reminder_module.changeset(attrs)
        |> Repo.insert()

      contents =
        safe_inputs_for(changeset, :channel, :sms, polymorphic?, fn f ->
          assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset

          assert %{
                   country_code: {"can't be blank", [validation: :required]},
                   provider: {"can't be blank", [validation: :required]}
                 } = Map.new(f.errors)

          text_input(f, :number)
        end)

      expected_contents =
        if(polymorphic?,
          do:
            ~s(<input id="reminder_channel___type__" name="reminder[channel][__type__]" type="hidden" value="sms"><input id="reminder_channel_number" name="reminder[channel][number]" type="text" value="1">),
          else:
            ~s(<input id="reminder_channel_number" name="reminder[channel][number]" type="text" value="1">)
        )

      assert contents == expected_contents

      contents =
        safe_inputs_for(
          Map.put(changeset, :action, :insert),
          :channel,
          :sms,
          polymorphic?,
          fn f ->
            assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
            text_input(f, :number)
          end
        )

      expected_contents =
        if(polymorphic?,
          do:
            ~s(<input id="reminder_channel___type__" name="reminder[channel][__type__]" type="hidden" value="sms"><input id="reminder_channel_number" name="reminder[channel][number]" type="text" value="1">),
          else:
            ~s(<input id="reminder_channel_number" name="reminder[channel][number]" type="text" value="1">)
        )

      assert contents == expected_contents
    end
  end

  test "inputs_for/4 after invalid insert with valid nested struct" do
    for polymorphic? <- [false, true] do
      reminder_module = get_module(Reminder, polymorphic?)

      attrs = %{
        text: "This is an SMS reminder",
        channel: %{
          my_type_field: "sms",
          number: "02/807.05.53",
          country_code: 1,
          provider: %{
            __type__: "twilio",
            api_key: "foo"
          }
        }
      }

      {:error, changeset} =
        struct(reminder_module)
        |> reminder_module.changeset(attrs)
        |> Repo.insert()

      assert match?(
               content when is_binary(content),
               safe_inputs_for(changeset, :channel, :sms, polymorphic?, fn f ->
                 assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset

                 assert %{} = Map.new(f.errors)

                 text_input(f, :number)
               end)
             )
    end
  end

  describe "get_polymorphic_type/3" do
    test "returns the type for a module" do
      assert PolymorphicEmbed.get_polymorphic_type(
               PolymorphicEmbed.Reminder,
               :channel,
               PolymorphicEmbed.Channel.SMS
             ) == :sms
    end

    test "returns the type for a struct" do
      assert PolymorphicEmbed.get_polymorphic_type(
               PolymorphicEmbed.Reminder,
               :channel,
               %PolymorphicEmbed.Channel.Email{
                 address: "what",
                 confirmed: true
               }
             ) ==
               :email
    end
  end

  describe "get_polymorphic_module/3" do
    test "returns the module for a type" do
      assert PolymorphicEmbed.get_polymorphic_module(PolymorphicEmbed.Reminder, :channel, :sms) ==
               PolymorphicEmbed.Channel.SMS
    end
  end

  defp safe_inputs_for(changeset, field, type, polymorphic?, fun) do
    mark = "--PLACEHOLDER--"

    inputs_for_fun =
      if(polymorphic?,
        do: fn f -> polymorphic_embed_inputs_for(f, field, type, fun) end,
        else: fn f -> inputs_for(f, field, fun) end
      )

    contents =
      safe_to_string(
        form_for(changeset, "/", fn f ->
          html_escape([mark, inputs_for_fun.(f), mark])
        end)
      )

    [_, inner, _] = String.split(contents, mark)
    inner
  end
end
