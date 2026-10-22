defmodule PolymorphicEmbed.HTML.HelpersTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias PolymorphicEmbed.Channel.{Email, SMSAttempts, SMSResult, TwilioSMSProvider}
  alias PolymorphicEmbed.Country
  alias PolymorphicEmbed.HTML.Helpers
  alias PolymorphicEmbed.Reminder
  alias PolymorphicEmbed.Reminder.Context.{Age, Location}

  defmodule Group do
    use Ecto.Schema
    import PolymorphicEmbed

    embedded_schema do
      polymorphic_embeds_many(:contexts, types: [age: Age], on_replace: :delete)
    end

    def changeset(data, params) do
      data
      |> Changeset.cast(params, [])
      |> cast_polymorphic_embed(:contexts, sort_param: :order)
    end
  end

  defmodule Container do
    use Ecto.Schema
    import PolymorphicEmbed

    embedded_schema do
      polymorphic_embeds_one(:group, types: [group: Group], on_replace: :update)
    end
  end

  test "preserves sorted row parameters inside a valid single embed" do
    first = %{"__type__" => "age", "age" => "same", "_persistent_id" => "first"}
    second = %{"__type__" => "age", "age" => "same", "_persistent_id" => "second"}

    parent =
      %Container{}
      |> Changeset.cast(
        %{
          "group" => %{
            "__type__" => "group",
            "contexts" => %{"0" => first, "1" => second},
            "order" => ["1", "0"]
          }
        },
        []
      )
      |> PolymorphicEmbed.cast_polymorphic_embed(:group)

    [group] = forms(parent, :group)
    rows = Helpers.to_form(group.source, group, :contexts, [])
    assert Enum.map(rows, & &1.params) == [second, first]
  end

  test "keeps row parameters through sorting, dropping and ignored types" do
    first = %{"__type__" => "age", "age" => "same", "_persistent_id" => "first"}
    second = %{"__type__" => "age", "age" => "same", "_persistent_id" => "second"}
    invalid = %{"__type__" => "location", "address" => "", "_persistent_id" => "invalid"}

    params = %{
      "contexts2" => %{
        "0" => first,
        "1" => second,
        "2" => invalid,
        "3" => %{"__type__" => "unknown"},
        "4" => %{"__type__" => "age", "age" => "dropped"}
      },
      "order" => ["1", "2", "3", "4", "0"],
      "remove" => ["4"]
    }

    options = [sort_param: :order, drop_param: :remove]

    changeset =
      %Reminder{}
      |> Changeset.cast(params, [])
      |> PolymorphicEmbed.cast_polymorphic_embed(:contexts2, options)

    forms = forms(changeset, :contexts2)
    assert Enum.map(forms, & &1.params) == [second, invalid, first]
    assert Enum.map(forms, & &1.data.__struct__) == [Age, Location, Age]
    assert Enum.map(forms, & &1.source.valid?) == [true, false, true]

    recast = PolymorphicEmbed.cast_polymorphic_embed(changeset, :contexts2, options)
    assert Enum.map(forms(recast, :contexts2), & &1.params) == [second, invalid, first]
  end

  test "uses numeric row order without an explicit sort parameter" do
    earlier = %{"__type__" => "age", "age" => "earlier", "_persistent_id" => "two"}
    later = %{"__type__" => "age", "age" => "later", "_persistent_id" => "ten"}

    changeset =
      %Reminder{}
      |> Changeset.cast(%{"contexts" => %{"10" => later, "2" => earlier}}, [])
      |> PolymorphicEmbed.cast_polymorphic_embed(:contexts)

    assert Enum.map(forms(changeset, :contexts), & &1.params) == [earlier, later]
  end

  test "keeps parameters for a valid row created by sort without field parameters" do
    options = [sort_param: :order, default_type_on_sort_create: :age]

    changeset =
      %Reminder{}
      |> Changeset.cast(%{"order" => ["new"]}, [])
      |> PolymorphicEmbed.cast_polymorphic_embed(:contexts, options)

    assert [%{data: %Age{}, params: %{"__type__" => :age}}] = forms(changeset, :contexts)

    recast = PolymorphicEmbed.cast_polymorphic_embed(changeset, :contexts, options)
    assert [%{data: %Age{}, params: %{"__type__" => :age}}] = forms(recast, :contexts)
  end

  test "keeps list parameters aligned after an unknown type is ignored" do
    row = %{"__type__" => "age", "age" => "kept", "_persistent_id" => "kept"}

    changeset =
      %Reminder{}
      |> Changeset.cast(%{"contexts2" => [%{"__type__" => "unknown"}, row]}, [])
      |> PolymorphicEmbed.cast_polymorphic_embed(:contexts2)

    assert [%{params: ^row}] = forms(changeset, :contexts2)
  end

  for {parent_action, child_action, effective_action, show_errors?} <- [
        {nil, :insert, nil, false},
        {:ignore, :insert, :ignore, false},
        {:insert, nil, :insert, true},
        {:validate, nil, :validate, true},
        {:validate, :update, :update, true},
        {:insert, :ignore, :ignore, false}
      ] do
    test "prepares child action #{inspect(child_action)} with parent action #{inspect(parent_action)}" do
      child =
        %Email{}
        |> Email.changeset(%{"address" => "a"})
        |> Map.put(:action, unquote(child_action))

      parent =
        %Reminder{}
        |> Changeset.change()
        |> Changeset.put_change(:channel, child)
        |> Map.put(:action, unquote(parent_action))

      [form] = forms(parent, :channel)
      assert form.action == unquote(parent_action)
      assert form.source.action == unquote(effective_action)
      assert form.source.errors == child.errors
      refute form.source.valid?
      assert form.errors == if(unquote(show_errors?), do: child.errors, else: [])
      assert Phoenix.Component.to_form(form.source).errors == form.errors
    end
  end

  test "assigns the parent action when preparing a struct" do
    for action <- [:insert, :validate] do
      parent =
        %Reminder{channel: %Email{address: "valid"}}
        |> Changeset.change()
        |> Map.put(:action, action)

      [form] = forms(parent, :channel)
      assert form.source.action == action
      assert form.errors == []
    end
  end

  test "retains nested errors when another form uses the prepared source" do
    child = Location.changeset(%Location{}, %{address: "valid", country: %{name: "A"}})

    parent =
      %Reminder{}
      |> Changeset.change()
      |> Changeset.put_change(:contexts, [child])
      |> Map.put(:action, :insert)

    [form] = forms(parent, :contexts)
    rebuilt = Phoenix.Component.to_form(form.source)

    [country] = Phoenix.HTML.FormData.to_form(form.source, rebuilt, :country, [])
    assert country.errors == child.changes.country.errors
    assert country.errors != []
  end

  test "reads nested embeds of valid rows from data instead of parameters" do
    params = %{
      "contexts" => %{
        "0" => %{
          "__type__" => "location",
          "address" => "first",
          "country" => %{"name" => "Belgium"},
          "_persistent_id" => "first"
        }
      }
    }

    changeset =
      %Reminder{}
      |> Changeset.cast(params, [])
      |> PolymorphicEmbed.cast_polymorphic_embed(:contexts)
      |> Map.put(:action, :validate)

    [form] = forms(changeset, :contexts)
    assert form.params["_persistent_id"] == "first"
    assert form[:address].value == "first"
    assert %Country{name: "Belgium"} = form[:country].value
  end

  test "reads nested embeds of a valid single embed from data instead of parameters" do
    params = %{
      "channel" => %{
        "my_type_field" => "sms",
        "number" => "02/807.05.53",
        "country_code" => "1",
        "result" => %{"success" => "true"},
        "attempts" => %{"0" => %{"date" => "2020-05-28T07:27:05Z"}},
        "provider" => %{"__type__" => "twilio", "api_key" => "foo"}
      }
    }

    changeset =
      %Reminder{}
      |> Changeset.cast(params, [])
      |> PolymorphicEmbed.cast_polymorphic_embed(:channel)
      |> Map.put(:action, :validate)

    [form] = forms(changeset, :channel)
    assert form[:number].value == "02/807.05.53"
    assert %SMSResult{success: true} = form[:result].value
    assert [%SMSAttempts{}] = form[:attempts].value
    assert %TwilioSMSProvider{api_key: "foo"} = form[:provider].value
  end

  defp forms(changeset, field) do
    Helpers.to_form(changeset, Phoenix.Component.to_form(changeset), field, [])
  end
end
