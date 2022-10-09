defmodule PolymorphicEmbedTest do
  use ExUnit.Case

  doctest PolymorphicEmbed

  import Phoenix.Component
  import Phoenix.HTML
  import Phoenix.HTML.Form
  import Phoenix.LiveViewTest
  import PolymorphicEmbed.HTML.Form

  alias PolymorphicEmbed.Repo

  @generators [:not_polymorphic, :polymorphic]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp get_module(name, :polymorphic),
    do: Module.concat([PolymorphicEmbed, name])

  defp get_module(name, :not_polymorphic),
    do: Module.concat([PolymorphicEmbed.Regular, name])

  test "receive embed as map of values" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      sms_reminder_attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder #{generator}",
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
        |> QueryBuilder.where(text: "This is an SMS reminder #{generator}")
        |> Repo.one()

      assert get_module(Channel.SMS, generator) == reminder.channel.__struct__

      assert get_module(Channel.TwilioSMSProvider, generator) ==
               reminder.channel.provider.__struct__

      assert get_module(Channel.SMSResult, generator) == reminder.channel.result.__struct__
      assert true == reminder.channel.result.success
      assert ~U[2020-05-28 07:27:05Z] == hd(reminder.channel.attempts).date

      assert Map.has_key?(reminder.channel, :id)
      assert reminder.channel.id

      sms_module = get_module(Channel.SMS, generator)

      sms_reminder_attrs = %{
        channel: %{
          country_code: 2
        }
      }

      {:ok, update_result} =
        reminder
        |> reminder_module.changeset(sms_reminder_attrs)
        |> Repo.update()

      assert reminder.channel.id == update_result.channel.id

      # test changing entity

      sms_module =
        struct(sms_module,
          id: 10,
          country_code: 10
        )

      sms_changeset = Ecto.Changeset.change(sms_module)

      {:ok, update_result} =
        reminder
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:channel, nil)
        |> Repo.update()

      {:ok, _} =
        update_result
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:channel, sms_changeset)
        |> Repo.update()
    end
  end

  test "validations before casting polymorphic embed still work" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      sms_reminder_attrs = %{
        text: "This is an SMS reminder #{generator}",
        contexts: [
          %{
            __type__: "location",
            address: "Foo St."
          },
          %{
            __type__: "location",
            address: "Bar St."
          }
        ]
      }

      insert_result =
        struct(reminder_module)
        |> reminder_module.changeset(sms_reminder_attrs)
        |> Repo.insert()

      assert {:error, changeset} = insert_result

      assert changeset.errors == [date: {"can't be blank", [validation: :required]}]
      refute changeset.valid?
    end
  end

  test "invalid values" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

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

  test "traverse_errors" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      sms_reminder_attrs = %{
        text: "This is an SMS reminder",
        channel: %{
          my_type_field: "sms"
        },
        contexts: [
          %{
            __type__: "location",
            address: "hello",
            country: %{
              name: ""
            }
          },
          %{
            __type__: "location",
            address: ""
          }
        ]
      }

      changeset =
        struct(reminder_module)
        |> reminder_module.changeset(sms_reminder_attrs)

      insert_result = Repo.insert(changeset)

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
                  },
                  contexts: [
                    %{
                      action: :insert,
                      valid?: false,
                      errors: context1_errors,
                      changes: %{
                        country: %{
                          action: :insert,
                          valid?: false,
                          errors: country_errors
                        }
                      }
                    },
                    %{
                      action: :insert,
                      valid?: false,
                      errors: context2_errors
                    }
                  ]
                }
              }} = insert_result

      assert %{
               number: {"can't be blank", [validation: :required]},
               country_code: {"can't be blank", [validation: :required]},
               provider: {"can't be blank", [validation: :required]}
             } = Map.new(channel_errors)

      assert [date: {"can't be blank", [validation: :required]}] = changeset.errors
      assert [date: {"can't be blank", [validation: :required]}] = errors

      assert [] = context1_errors
      assert %{address: {"can't be blank", [validation: :required]}} = Map.new(context2_errors)
      assert %{name: {"can't be blank", [validation: :required]}} = Map.new(country_errors)

      traverse_errors_fun =
        if polymorphic?(generator) do
          &PolymorphicEmbed.traverse_errors/2
        else
          &Ecto.Changeset.traverse_errors/2
        end

      %{
        channel: %{
          country_code: ["can't be blank"],
          number: ["can't be blank"],
          provider: ["can't be blank"]
        },
        contexts: [%{country: %{name: ["can't be blank"]}}, %{address: ["can't be blank"]}],
        date: ["can't be blank"]
      } =
        traverse_errors_fun.(
          changeset,
          fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end
        )
    end
  end

  test "traverse_errors on changesets with valid polymorphic structs" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      sms_reminder_attrs = %{
        text: "This is an SMS reminder",
        channel: %{
          my_type_field: "sms",
          number: "02/807.05.53",
          country_code: 1,
          provider: %{__type__: "twilio", api_key: "somekey"}
        },
        contexts: [
          %{
            __type__: "location",
            address: "hello",
            country: %{
              name: ""
            }
          },
          %{
            __type__: "location",
            address: ""
          }
        ]
      }

      changeset =
        struct(reminder_module)
        |> reminder_module.changeset(sms_reminder_attrs)

      insert_result = Repo.insert(changeset)

      assert {:error,
              %Ecto.Changeset{
                action: :insert,
                valid?: false,
                errors: errors,
                changes: %{
                  contexts: [
                    %{
                      action: :insert,
                      valid?: false,
                      errors: context1_errors,
                      changes: %{
                        country: %{
                          action: :insert,
                          valid?: false,
                          errors: country_errors
                        }
                      }
                    },
                    %{
                      action: :insert,
                      valid?: false,
                      errors: context2_errors
                    }
                  ]
                }
              }} = insert_result

      assert [date: {"can't be blank", [validation: :required]}] = changeset.errors
      assert [date: {"can't be blank", [validation: :required]}] = errors

      assert [] = context1_errors
      assert %{address: {"can't be blank", [validation: :required]}} = Map.new(context2_errors)
      assert %{name: {"can't be blank", [validation: :required]}} = Map.new(country_errors)

      traverse_errors_fun =
        if polymorphic?(generator) do
          &PolymorphicEmbed.traverse_errors/2
        else
          &Ecto.Changeset.traverse_errors/2
        end

      %{
        contexts: [%{country: %{name: ["can't be blank"]}}, %{address: ["can't be blank"]}],
        date: ["can't be blank"]
      } =
        traverse_errors_fun.(
          changeset,
          fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end
        )
    end
  end

  test "receive embed as struct" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)
      sms_module = get_module(Channel.SMS, generator)
      sms_provider_module = get_module(Channel.TwilioSMSProvider, generator)
      sms_result_module = get_module(Channel.SMSResult, generator)
      sms_attempts_module = get_module(Channel.SMSAttempts, generator)

      reminder =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an SMS reminder #{generator}",
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
        |> QueryBuilder.where(text: "This is an SMS reminder #{generator}")
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

  test "cannot generate IDs if struct didn't go through cast_polymorphic_embed/3" do
    generator = :polymorphic

    reminder_module = get_module(Reminder, generator)
    sms_module = get_module(Channel.SMS, generator)

    reminder =
      struct(reminder_module,
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder #{generator}",
        channel:
          struct(sms_module,
            country_code: 1,
            number: "02/807.05.53"
          )
      )

    assert_raise RuntimeError,
                 ~r"polymorphic_embed is not able to add an autogenerated key without casting through cast_polymorphic_embed/3",
                 fn ->
                   Repo.insert(reminder)
                 end
  end

  test "without __type__" do
    generator = :polymorphic
    reminder_module = get_module(Reminder, generator)
    email_module = get_module(Channel.Email, generator)

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

  test "wrong type as string adds error in changeset" do
    generator = :polymorphic
    reminder_module = get_module(Reminder, generator)

    attrs = %{
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an Email reminder",
      channel: %{
        my_type_field: "unknown type"
      }
    }

    insert_result =
      struct(reminder_module)
      |> reminder_module.changeset(attrs)
      |> Repo.insert()

    assert {:error, %Ecto.Changeset{errors: [channel: {"is invalid", []}]}} = insert_result
  end

  test "wrong type as string raises" do
    generator = :polymorphic
    reminder_module = get_module(Reminder, generator)

    sms_reminder_attrs = %{
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an SMS reminder",
      channel: %{
        my_type_field: "sms",
        number: "02/807.05.53",
        country_code: 1,
        result: %{success: true},
        attempts: [],
        provider: %{
          __type__: "unknown type",
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

  test "pass non-changeset as first argument to cast_polymorphic_embed/3 should fail" do
    generator = :polymorphic

    reminder_module = get_module(Reminder, generator)

    assert_raise RuntimeError,
                 ~r"cast_polymorphic_embed/3 only accepts a changeset as first argument",
                 fn ->
                   PolymorphicEmbed.cast_polymorphic_embed(struct(reminder_module), :channel)
                 end
  end

  test "cast embed after change/2 call should succeed" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      changeset = Ecto.Changeset.change(struct(reminder_module))

      changeset =
        if polymorphic?(generator) do
          PolymorphicEmbed.cast_polymorphic_embed(changeset, :channel)
        else
          Ecto.Changeset.cast_embed(changeset, :channel)
        end

      assert changeset.valid?
      assert map_size(changeset.changes) == 0
    end
  end

  test "loading a nil embed" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      insert_result =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an Email reminder #{generator}",
          channel: nil
        )
        |> Repo.insert()

      assert {:ok, %reminder_module{}} = insert_result

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an Email reminder #{generator}")
        |> Repo.one()

      assert is_nil(reminder.channel)
    end
  end

  test "casting a nil embed" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an Email reminder #{generator}",
        channel: nil
      }

      insert_result =
        struct(reminder_module)
        |> reminder_module.changeset(attrs)
        |> Repo.insert()

      assert {:ok, %reminder_module{}} = insert_result

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an Email reminder #{generator}")
        |> Repo.one()

      assert is_nil(reminder.channel)
    end
  end

  test "required true" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      sms_reminder_attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder #{generator}",
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

  test "custom changeset by passing MFA" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)
      sms_module = get_module(Channel.SMS, generator)

      sms_reminder_attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder #{generator}",
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

      assert {:ok, reminder} = insert_result
      assert reminder.channel.custom

      %reminder_module{} = reminder

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an SMS reminder #{generator}")
        |> Repo.one()

      assert sms_module == reminder.channel.__struct__
    end
  end

  test "custom changeset by passing function" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)
      sms_module = get_module(Channel.SMS, generator)

      sms_reminder_attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder #{generator}",
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
        |> reminder_module.custom_changeset2(sms_reminder_attrs)
        |> Repo.insert()

      assert {:ok, reminder} = insert_result
      assert reminder.channel.custom

      %reminder_module{} = reminder

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an SMS reminder #{generator}")
        |> Repo.one()

      assert sms_module == reminder.channel.__struct__
    end
  end

  test "with option but not for all" do
    generator = :polymorphic
    reminder_module = get_module(Reminder, generator)
    email_module = get_module(Channel.Email, generator)

    sms_reminder_attrs = %{
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an Email reminder",
      channel: %{
        my_type_field: "email",
        address: "john@example.com",
        valid: true,
        confirmed: false
      }
    }

    insert_result =
      struct(reminder_module)
      |> reminder_module.custom_changeset2(sms_reminder_attrs)
      |> Repo.insert()

    assert {:ok, reminder} = insert_result

    %reminder_module{} = reminder

    reminder =
      reminder_module
      |> QueryBuilder.where(text: "This is an Email reminder")
      |> Repo.one()

    assert email_module == reminder.channel.__struct__
  end

  test "setting embed to nil" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)
      sms_module = get_module(Channel.SMS, generator)

      attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an SMS reminder #{generator}",
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
        |> QueryBuilder.where(text: "This is an SMS reminder #{generator}")
        |> Repo.one()

      assert is_nil(reminder.channel)
    end
  end

  test "omitting embed field in cast" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)
      sms_module = get_module(Channel.SMS, generator)

      attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is an Email reminder #{generator}"
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
        |> QueryBuilder.where(text: "This is an Email reminder #{generator}")
        |> Repo.one()

      refute is_nil(reminder.channel)
    end
  end

  test "keep existing data" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)
      sms_module = get_module(Channel.SMS, generator)
      sms_provider_module = get_module(Channel.TwilioSMSProvider, generator)
      sms_result_module = get_module(Channel.SMSResult, generator)
      sms_attempts_module = get_module(Channel.SMSAttempts, generator)

      reminder =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an SMS reminder #{generator}",
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

      reminder =
        reminder
        |> reminder_module.changeset(%{})
        |> Repo.insert!()

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
        |> QueryBuilder.where(text: "This is an SMS reminder #{generator}")
        |> Repo.one()

      assert reminder.channel.result.success
    end
  end

  test "params with string keys" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)
      sms_module = get_module(Channel.SMS, generator)
      sms_provider_module = get_module(Channel.TwilioSMSProvider, generator)
      sms_result_module = get_module(Channel.SMSResult, generator)
      sms_attempts_module = get_module(Channel.SMSAttempts, generator)

      reminder =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an SMS reminder #{generator}",
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

      reminder =
        reminder
        |> reminder_module.changeset(%{})
        |> Repo.insert!()

      changeset =
        reminder
        |> reminder_module.changeset(%{
          "channel" => %{
            "my_type_field" => "sms",
            "number" => "54"
          }
        })

      Repo.update!(changeset)

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is an SMS reminder #{generator}")
        |> Repo.one()

      assert reminder.channel.result.success
    end
  end

  test "missing __type__ leads to changeset error" do
    generator = :polymorphic
    reminder_module = get_module(Reminder, generator)

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

  test "missing __type__ nilifies" do
    generator = :polymorphic
    reminder_module = get_module(Reminder, generator)

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
          __type__: "twilio",
          api_key: "foo"
        },
        fallback_provider: %{
          api_key: "foo"
        }
      }
    }

    insert_result =
      struct(reminder_module)
      |> reminder_module.changeset(sms_reminder_attrs)
      |> Repo.insert()

    assert {:ok, %{channel: %{fallback_provider: nil}}} = insert_result
  end

  test "missing __type__ leads to raising error" do
    generator = :polymorphic
    reminder_module = get_module(Reminder, generator)

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
    generator = :polymorphic
    reminder_module = get_module(Reminder, generator)
    sms_module = get_module(Channel.SMS, generator)

    struct(reminder_module,
      date: ~U[2020-05-28 02:57:19Z],
      text: "This is an SMS reminder",
      channel:
        struct(sms_module,
          country_code: 1,
          number: "02/807.05.53"
        )
    )
    |> reminder_module.changeset(%{})
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
    generator = :polymorphic
    reminder_module = get_module(Reminder, generator)
    sms_module = get_module(Channel.SMS, generator)

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

    assert {:ok, %reminder_module{}} = update_result

    reminder =
      reminder_module
      |> QueryBuilder.where(text: "This is an SMS reminder")
      |> Repo.one()

    assert sms_module == reminder.channel.__struct__
  end

  test "supports lists of polymorphic embeds" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is a reminder with multiple contexts #{generator}",
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
            ref: "12345",
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

      reminder =
        struct(reminder_module)
        |> reminder_module.changeset(attrs)
        |> Repo.insert!()

      Enum.each(reminder.contexts, fn context ->
        assert context.id
      end)

      reminder =
        reminder_module
        |> QueryBuilder.where(text: "This is a reminder with multiple contexts #{generator}")
        |> Repo.one()

      assert reminder.contexts |> length() == 2

      Enum.each(reminder.contexts, fn context ->
        assert context.id
      end)

      if polymorphic?(generator) do
        assert Enum.at(reminder.contexts, 0).ref == "12345"
        assert Enum.at(reminder.contexts, 0).type == "cellphone"
        assert Enum.at(reminder.contexts, 1).age == "aquarius"
      else
        assert Enum.at(reminder.contexts, 0).address == "address"
        assert Enum.at(reminder.contexts, 1).address == "address"
      end

      # add new list of contexts and assert that we have different ids

      attrs = %{
        contexts: [
          %{
            __type__: "device",
            ref: "12345",
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

      updated_reminder =
        reminder
        |> reminder_module.changeset(attrs)
        |> Repo.update!()

      assert Enum.at(reminder.contexts, 0).id != Enum.at(updated_reminder.contexts, 0).id
      assert Enum.at(reminder.contexts, 1).id != Enum.at(updated_reminder.contexts, 1).id
    end
  end

  test "generate ID for single embed in data" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)
      sms_module = get_module(Channel.SMS, generator)

      struct =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an SMS reminder #{generator}",
          channel: struct(sms_module)
        )

      changeset = reminder_module.changeset(struct, %{})

      if polymorphic?(generator) do
        assert changeset.changes.channel.id
      else
        assert map_size(changeset.changes) == 0
      end

      struct = Repo.insert!(changeset)

      if polymorphic?(generator) do
        assert changeset.changes.channel.id == struct.channel.id
      else
        assert struct.channel.id
      end
    end
  end

  test "generate ID for single embed in changes" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      struct =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an SMS reminder #{generator}"
        )

      changeset =
        reminder_module.changeset(
          struct,
          %{
            channel: %{
              my_type_field: "sms",
              number: "111",
              country_code: 1,
              provider: %{
                __type__: "twilio",
                api_key: "foo"
              }
            }
          }
        )

      if polymorphic?(generator) do
        assert changeset.changes.channel.id
      else
        refute Map.has_key?(changeset.changes.channel, :id)
      end

      struct = Repo.insert!(changeset)

      if polymorphic?(generator) do
        assert changeset.changes.channel.id == struct.channel.id
      else
        assert struct.channel.id
      end
    end
  end

  test "generate ID for list of embeds in data" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)
      location_module = get_module(Reminder.Context.Location, generator)

      struct =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an SMS reminder #{generator}",
          contexts: [
            struct(location_module),
            struct(location_module)
          ]
        )

      changeset = reminder_module.changeset(struct, %{})

      if polymorphic?(generator) do
        assert Enum.at(changeset.changes.contexts, 0).id
        assert Enum.at(changeset.changes.contexts, 1).id
      else
        assert map_size(changeset.changes) == 0
      end

      struct = Repo.insert!(changeset)

      if polymorphic?(generator) do
        assert Enum.at(changeset.changes.contexts, 0).id == Enum.at(struct.contexts, 0).id
        assert Enum.at(changeset.changes.contexts, 1).id == Enum.at(struct.contexts, 1).id
      else
        assert Enum.at(struct.contexts, 0).id
        assert Enum.at(struct.contexts, 1).id
      end
    end
  end

  test "generate ID for list of embeds in changes" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      struct =
        struct(reminder_module,
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is an SMS reminder #{generator}"
        )

      changeset =
        reminder_module.changeset(
          struct,
          %{
            contexts: [
              %{__type__: "location", address: "A"},
              %{__type__: "location", address: "B"}
            ]
          }
        )

      if polymorphic?(generator) do
        assert Enum.at(changeset.changes.contexts, 0).id
        assert Enum.at(changeset.changes.contexts, 1).id
      else
        refute Map.has_key?(Enum.at(changeset.changes.contexts, 0), :id)
      end

      struct = Repo.insert!(changeset)

      if polymorphic?(generator) do
        assert Enum.at(changeset.changes.contexts, 0).id == Enum.at(struct.contexts, 0).id
        assert Enum.at(changeset.changes.contexts, 1).id == Enum.at(struct.contexts, 1).id
      else
        assert Enum.at(struct.contexts, 0).id
        assert Enum.at(struct.contexts, 1).id
      end
    end
  end

  test "validates lists of polymorphic embeds" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      attrs = %{
        date: ~U[2020-05-28 02:57:19Z],
        text: "This is a reminder with multiple contexts",
        contexts: [
          %{
            ref: "12345",
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

      if polymorphic?(generator) do
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

      if polymorphic?(generator) do
        attrs = %{
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is a reminder with multiple contexts",
          contexts2: [
            %{
              ref: "12345",
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

        insert_result =
          struct(reminder_module)
          |> reminder_module.changeset(attrs)
          |> Repo.insert()

        assert {:ok,
                %{
                  contexts2: [
                    %{
                      age: "aquarius"
                    }
                  ]
                }} = insert_result

        attrs = %{
          date: ~U[2020-05-28 02:57:19Z],
          text: "This is a reminder with multiple contexts",
          contexts: [
            %{
              __type__: "device",
              ref: "12345"
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

        device_module = get_module(Reminder.Context.Device, generator)

        reminder =
          struct(reminder_module,
            date: ~U[2020-05-28 02:57:19Z],
            text: "This is an SMS reminder #{generator}",
            contexts: [
              struct(device_module, ref: "12345")
            ]
          )

        attrs = %{
          contexts: [
            %{
              __type__: "device",
              ref: "54321"
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

  test "list of embeds defaults to []" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      assert struct(reminder_module).contexts == []
    end
  end

  test "list of embeds defaults to [] after insert" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      sms_reminder_attrs = %{
        text: "This is an SMS reminder #{generator}",
        date: DateTime.utc_now()
      }

      assert {:ok, inserted_result} =
               struct(reminder_module)
               |> reminder_module.changeset(sms_reminder_attrs)
               |> Repo.insert()

      assert inserted_result.contexts == []
    end
  end

  describe "polymorphic_embed_inputs_for/2" do
    test "generates forms that can be rendered" do
      reminder_module = get_module(Reminder, :polymorphic)

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
        reminder_module
        |> struct()
        |> reminder_module.changeset(attrs)

      html =
        render_component(
          &liveview_form/1,
          %{changeset: changeset, field: :channel}
        )
        |> Floki.parse_fragment!()

      assert [input] = Floki.find(html, "#reminder_channel___type__")
      assert Floki.attribute(input, "type") == ["hidden"]
      assert Floki.attribute(input, "value") == ["email"]

      assert [input] = Floki.find(html, "#reminder_channel_number")
      assert Floki.attribute(input, "type") == ["text"]
    end
  end

  test "inputs_for/4" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

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
        safe_inputs_for(changeset, :channel, generator, fn f ->
          assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
          assert f.errors == []
          text_input(f, :address)
        end)

      expected_contents =
        if(polymorphic?(generator),
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
          generator,
          fn f ->
            assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
            text_input(f, :address)
          end
        )

      expected_contents =
        if(polymorphic?(generator),
          do:
            ~s(<input id="reminder_channel___type__" name="reminder[channel][__type__]" type="hidden" value="email"><input id="reminder_channel_address" name="reminder[channel][address]" type="text" value="a">),
          else:
            ~s(<input id="reminder_channel_address" name="reminder[channel][address]" type="text" value="a">)
        )

      assert contents == expected_contents
    end
  end

  test "inputs_for/4 after invalid insert" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

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
        safe_inputs_for(changeset, :channel, generator, fn f ->
          assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset

          assert %{
                   country_code: {"can't be blank", [validation: :required]},
                   provider: {"can't be blank", [validation: :required]}
                 } = Map.new(f.errors)

          text_input(f, :number)
        end)

      expected_contents =
        if(polymorphic?(generator),
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
          generator,
          fn f ->
            assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
            text_input(f, :number)
          end
        )

      expected_contents =
        if(polymorphic?(generator),
          do:
            ~s(<input id="reminder_channel___type__" name="reminder[channel][__type__]" type="hidden" value="sms"><input id="reminder_channel_number" name="reminder[channel][number]" type="text" value="1">),
          else:
            ~s(<input id="reminder_channel_number" name="reminder[channel][number]" type="text" value="1">)
        )

      assert contents == expected_contents
    end
  end

  test "inputs_for/4 after invalid insert with valid nested struct" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

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
               safe_inputs_for(changeset, :channel, generator, fn f ->
                 assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset

                 assert %{} = Map.new(f.errors)

                 text_input(f, :number)
               end)
             )
    end
  end

  test "errors in form for polymorphic embed and nested embed" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      sms_reminder_attrs = %{
        text: "This is an SMS reminder",
        channel: %{
          my_type_field: "sms",
          result: %{
            success: ""
          }
        },
        contexts: [
          %{
            __type__: "location",
            address: "hello",
            country: %{
              name: "A"
            }
          },
          %{
            __type__: "location",
            address: ""
          }
        ]
      }

      changeset =
        reminder_module
        |> struct()
        |> reminder_module.changeset(sms_reminder_attrs)

      changeset = %{changeset | action: :insert}

      safe_form_for(changeset, fn f ->
        assert f.errors == [date: {"can't be blank", [validation: :required]}]

        contents =
          safe_inputs_for(changeset, :channel, generator, fn f ->
            assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset

            assert f.errors == [
                     number: {"can't be blank", [validation: :required]},
                     country_code: {"can't be blank", [validation: :required]},
                     provider: {"can't be blank", [validation: :required]}
                   ]

            contents =
              safe_inputs_for(f.source, :result, :not_polymorphic, fn f ->
                assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset

                assert f.errors == [success: {"can't be blank", [validation: :required]}]

                "from safe_inputs_for #{generator}"
              end)

            assert contents =~ "from safe_inputs_for #{generator}"

            "from safe_inputs_for #{generator}"
          end)

        assert contents =~ "from safe_inputs_for #{generator}"

        contents =
          safe_inputs_for(changeset, :contexts, generator, fn %{index: index} = f ->
            assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset

            if index == 0 do
              assert f.errors == []
            else
              assert f.errors == [address: {"can't be blank", [validation: :required]}]
            end

            contents =
              safe_inputs_for(f.source, :country, :not_polymorphic, fn f ->
                assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset

                if index == 0 do
                  assert f.errors == [
                           name:
                             {"should be at least %{count} character(s)",
                              [count: 3, validation: :length, kind: :min, type: :string]}
                         ]
                else
                  assert f.errors == []
                end

                "from safe_inputs_for #{generator}"
              end)

            assert contents =~ "from safe_inputs_for #{generator}"

            "from safe_inputs_for #{generator}"
          end)

        assert contents =~ "from safe_inputs_for #{generator}"

        1
      end)
    end
  end

  test "keep changes in embeds_one (nested into a polymorphic embed) when invalid changeset" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      sms_reminder_attrs = %{
        text: "This is an SMS reminder",
        channel: %{
          my_type_field: "sms",
          result: %{
            success: true
          }
        }
      }

      changeset =
        struct(reminder_module)
        |> reminder_module.changeset(sms_reminder_attrs)

      changeset = %{changeset | action: :insert}

      safe_form_for(changeset, fn f ->
        assert f.errors == [date: {"can't be blank", [validation: :required]}]

        contents =
          safe_inputs_for(changeset, :channel, generator, fn f ->
            contents =
              safe_inputs_for(f.source, :result, :not_polymorphic, fn f ->
                text_input(f, :success)
              end)

            expected_contents =
              ~s(<input id="sms_result_success" name="sms[result][success]" type="text" value="true">)

            assert contents == expected_contents

            "from safe_inputs_for #{generator}"
          end)

        assert contents =~ "from safe_inputs_for #{generator}"

        1
      end)
    end
  end

  test "form with polymorphic embed to nil" do
    for generator <- @generators do
      reminder_module = get_module(Reminder, generator)

      sms_reminder_attrs = %{
        text: "This is an SMS reminder",
        channel: nil,
        contexts: []
      }

      changeset =
        struct(reminder_module)
        |> reminder_module.changeset(sms_reminder_attrs)

      changeset = %{changeset | action: :insert}

      safe_form_for(changeset, fn f ->
        assert f.errors == [date: {"can't be blank", [validation: :required]}]

        contents =
          safe_inputs_for(changeset, :channel, generator, fn f ->
            contents =
              safe_inputs_for(f.source, :result, generator, fn f ->
                text_input(f, :success)
              end)

            expected_contents =
              ~s(<input id="sms_result_success" name="sms[result][success]" type="text">)

            assert contents == expected_contents

            assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
            assert f.errors == []

            "from safe_inputs_for #{generator}"
          end)

        expected =
          case generator do
            :polymorphic -> ""
            :not_polymorphic -> "from safe_inputs_for #{generator}"
          end

        assert contents =~ expected

        contents =
          safe_inputs_for(changeset, :contexts, generator, fn f ->
            assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
            assert f.errors == []

            safe_inputs_for(f.source, :country, false, fn f ->
              assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
              assert f.errors == []
            end)

            "from safe_inputs_for #{generator}"
          end)

        assert contents == ""

        1
      end)
    end
  end

  test "form with polymorphic embed to nil and given type" do
    reminder_module = get_module(Reminder, :polymorphic)

    sms_reminder_attrs = %{
      text: "This is an SMS reminder",
      channel: nil,
      contexts: []
    }

    changeset =
      struct(reminder_module)
      |> reminder_module.changeset(sms_reminder_attrs)

    changeset = %{changeset | action: :insert}

    safe_form_for(changeset, fn _f ->
      contents =
        safe_inputs_for(changeset, :channel, :sms, :polymorphic_with_type, fn f ->
          contents =
            safe_inputs_for(f.source, :result, :not_polymorphic, fn f ->
              text_input(f, :success)
            end)

          expected_contents =
            ~s(<input id="sms_result_success" name="sms[result][success]" type="text">)

          assert contents == expected_contents

          assert f.impl == Phoenix.HTML.FormData.Ecto.Changeset
          assert f.errors == []

          "from safe_inputs_for"
        end)

      assert contents =~ "from safe_inputs_for"
      1
    end)
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
             ) == :email
    end
  end

  describe "Form.get_polymorphic_type/3" do
    test "returns type from changeset" do
      reminder_module = get_module(Reminder, :polymorphic)

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
        reminder_module
        |> struct()
        |> reminder_module.changeset(attrs)

      safe_form_for(changeset, fn f ->
        assert PolymorphicEmbed.HTML.Form.get_polymorphic_type(f, reminder_module, :channel) ==
                 :email

        text_input(f, :text)
      end)
    end

    test "returns type from struct" do
      reminder_module = get_module(Reminder, :polymorphic)

      channel = %PolymorphicEmbed.Channel.Email{
        address: "a",
        valid: true,
        confirmed: true
      }

      changeset =
        reminder_module
        |> struct()
        |> Map.put(:channel, channel)
        |> reminder_module.changeset(%{})

      safe_form_for(changeset, fn f ->
        assert PolymorphicEmbed.HTML.Form.get_polymorphic_type(f, reminder_module, :channel) ==
                 :email

        text_input(f, :text)
      end)
    end

    test "returns type from string parameters" do
      reminder_module = get_module(Reminder, :polymorphic)
      attrs = %{"channel" => %{"my_type_field" => "email"}}

      changeset =
        reminder_module
        |> struct()
        |> reminder_module.changeset(attrs)

      safe_form_for(changeset, fn f ->
        assert PolymorphicEmbed.HTML.Form.get_polymorphic_type(f, reminder_module, :channel) ==
                 :email

        text_input(f, :text)
      end)
    end

    test "returns type from atom parameters" do
      reminder_module = get_module(Reminder, :polymorphic)
      attrs = %{channel: %{my_type_field: :email}}

      changeset =
        reminder_module
        |> struct()
        |> reminder_module.changeset(attrs)

      safe_form_for(changeset, fn f ->
        assert PolymorphicEmbed.HTML.Form.get_polymorphic_type(f, reminder_module, :channel) ==
                 :email

        text_input(f, :text)
      end)
    end

    test "returns type from parameters while type field is custom" do
      reminder_module = get_module(Reminder, :polymorphic)
      attrs = %{channel: %{__type__: :email}}

      changeset =
        reminder_module
        |> struct()
        |> reminder_module.changeset(attrs)

      safe_form_for(changeset, fn f ->
        assert PolymorphicEmbed.HTML.Form.get_polymorphic_type(f, reminder_module, :channel) ==
                 nil

        text_input(f, :text)
      end)
    end

    test "returns nil without source struct and __type__ parameter" do
      reminder_module = get_module(Reminder, :polymorphic)

      changeset =
        reminder_module
        |> struct()
        |> reminder_module.changeset(%{})

      safe_form_for(changeset, fn f ->
        assert PolymorphicEmbed.HTML.Form.get_polymorphic_type(f, reminder_module, :channel) ==
                 nil

        text_input(f, :text)
      end)
    end

    # https://github.com/mathieuprog/polymorphic_embed/issues/59#issuecomment-1255774332
    test "make sure that we do not 'absorb' atoms" do
      opts = [
        types: [
          sms: PolymorphicEmbed.Channel.SMS,
          email: [
            module: PolymorphicEmbed.Channel.Email,
            identify_by_fields: [:address, :confirmed]
          ]
        ],
        on_replace: :update,
        type_field: :my_type_field
      ]

      PolymorphicEmbed.init(opts)
      |> Map.fetch!(:types_metadata)
      |> Enum.each(fn %{type: type} ->
        assert is_atom(type)
      end)
    end
  end

  describe "types/2" do
    test "returns the types for a polymoprhic embed field" do
      assert PolymorphicEmbed.types(PolymorphicEmbed.Reminder, :channel) ==
               [:sms, :email]
    end
  end

  describe "get_polymorphic_module/3" do
    test "returns the module for a type" do
      assert PolymorphicEmbed.get_polymorphic_module(PolymorphicEmbed.Reminder, :channel, :sms) ==
               PolymorphicEmbed.Channel.SMS
    end
  end

  defp safe_inputs_for(changeset, field, embed_type \\ nil, test_type, fun) do
    mark = "--PLACEHOLDER--"

    inputs_for_fun =
      case test_type do
        :not_polymorphic ->
          fn f -> inputs_for(f, field, fun) end

        :polymorphic ->
          fn f -> polymorphic_embed_inputs_for(f, field, fun) end

        :polymorphic_with_type ->
          fn f -> polymorphic_embed_inputs_for(f, field, embed_type, fun) end
      end

    contents =
      safe_to_string(
        form_for(changeset, "/", fn f ->
          html_escape([mark, inputs_for_fun.(f), mark])
        end)
      )

    [_, inner, _] = String.split(contents, mark)
    inner
  end

  defp safe_form_for(changeset, opts \\ [], function) do
    safe_to_string(form_for(changeset, "/", opts, function))
  end

  defp liveview_form(assigns) do
    ~H"""
    <.form
      let={f}
      for={@changeset}
    >
      <%= for sms_form <- polymorphic_embed_inputs_for f, @field do %>
        <%= hidden_inputs_for(sms_form) %>
        <%= text_input sms_form, :number %>
      <% end %>
    </.form>
    """
  end

  defp polymorphic?(:polymorphic), do: true
  defp polymorphic?(:not_polymorphic), do: false
end
