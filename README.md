# Polymorphic embeds for Ecto

`polymorphic_embed` brings support for polymorphic/dynamic embedded schemas in Ecto.

Ecto's `embeds_one` macro requires a specific schema module to be specified. This library removes this restriction by
**dynamically** determining which schema to use, based on data to be stored (from a form or API) and retrieved (from the
data source).


## Usage

### Enable polymorphism

Let's say we want a schema `Reminder` representing a reminder for an event, that can be sent either by email or SMS.

We create the `Email` and `SMS` embedded schemas containing the fields that are specific for each of those communication
channels.

The `Reminder` schema can then contain a `:channel` field that will either hold an `Email` or `SMS` struct, by setting
its type to the custom type `PolymorphicEmbed` that this library provides.

Find the schema code and explanations below.

```elixir
defmodule MyApp.Reminder do
  use Ecto.Schema
  import Ecto.Changeset
  import PolymorphicEmbed, only: [cast_polymorphic_embed: 2]

  schema "reminders" do
    field :date, :utc_datetime
    field :text, :string

    field :channel, PolymorphicEmbed,
      types: [
        sms: MyApp.Channel.SMS,
        email: [module: MyApp.Channel.Email, identify_by_fields: [:address, :confirmed]]
      ]
  end

  def changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_polymorphic_embed(:channel)
    |> validate_required(:date)
  end
end
```

```elixir
defmodule MyApp.Channel.Email do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :address, :string
    field :confirmed, :boolean
  end

  def changeset(email, params) do
    email
    |> cast(params, ~w(address confirmed)a)
    |> validate_required(:address)
    |> validate_length(:address, min: 4)
  end
end
```

```elixir
defmodule MyApp.Channel.SMS do
  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field :number, :string
  end
end
```

The `:types` option for the `PolymorphicEmbed` custom type either contains a keyword list 
mapping an atom representing the type (in this example `:email` and `:sms`) with the corresponding 
embedded schema module, or specifies a function that can be used to map any type value into
a corresponding schema module.

There are four strategies to detect the right embedded schema to use:

1.
```elixir
[sms: MyApp.Channel.SMS]
```

When receiving parameters to be casted (e.g. from a form), we expect a `"__type__"` (or `:__type__`) parameter
containing the type of channel (`"email"` or `"sms"`).

2.
```elixir
[email: [
  module: MyApp.Channel.Email,
  identify_by_fields: [:address, :confirmed]]]
```

Here we specify how the type can be determined based on the presence of given fields. In this example, if the data
contains `:address` and `:confirmed` parameters (or their string version), the type is `:email`. A `"__type__"`
parameter is then no longer required.

Note that you may still include a `__type__` parameter that will take precedence over this strategy (this could still be
useful if you need to store incomplete data, which might not allow identifying the type).

3.
```elixir
# Converts an arbritary type atom or string key to a schema module, e.g. "email" to MyApp.Channel.Email
def lookup_type(key, :module) do
  case to_string(key) do
    "sms" -> MyApp.Channel.SMS
    _other -> Module.safe_concat(["MyApp.Channel", String.capitalize(key)])
  end
end

# Reverse lookup, converts the module to the appropriate type
def lookup_type(key, :type) do
  Module.split(key) 
  |> List.last() 
  |> String.downcase() 
  |> String.to_atom()
end


types: &MyModule.lookup_type/2
```

If you specify `types: &MyModule.lookup_type/2` with the format `&Mod.fun/arity` as in the example above,
you supply a reference to a 2-arity function that converts both ways between types and modules.
The first argument to the function is the key to be converted, and the second argument is 
either `:module` to convert from a type to a module, or `:key` to convert from a module to the type.
This allows you to embed arbitrary schemas without having to list
them all explicitly. The function should return an atom, not a string value.

4.
```elixir
types: :by_module
```

If you specify `types: :by_module`, the `"__type__"` (or `:__type__`) parameter should contain the fully qualified
and reachable module name of the embedded schema, such as "MyApp.Channel.Email". This is equivalent to specifying
`types: &MyModule.lookup_type/2`, where `lookup_type` was defined as:

```elixir
def lookup_type(key, :module), do: Module.safe_concat([to_string(key)])
def lookup_type(key, :type), do: key
```


### Options

* `:types` - discussed above.
* `:on_type_not_found` - specify whether to raise or add a changeset error if the embed's type cannot be inferred.
  Possible values are `:raise` and `:changeset_error`. By default, a changeset error "is invalid" is added.

### Displaying form inputs and errors in Phoenix templates

The library comes with a form helper in order to build form inputs for polymorphic embeds and display changeset errors.

In the entrypoint defining your web interface (`lib/your_app_web.ex` file), add the following import:

```elixir
def view do
  quote do
    # imports and stuff
    import PolymorphicEmbed.HTML.Form
  end
end
```

This provides you with a `polymorphic_embed_inputs_for/4` function.

Here is an example form using the imported function:

```elixir
<%= inputs_for f, :reminders, fn reminder_form -> %>
  <%= polymorphic_embed_inputs_for reminder_form, :channel, :sms, fn sms_form -> %>
    <div class="sms-inputs">
      <label>Number<label>
      <%= text_input sms_form, :number %>
      <div class="error">
        <%= error_tag sms_form, :number %>
      </div>
    </div>
  <% end %>
<% end %>
```

`polymorphic_embed_inputs_for/4` also renders a hidden input for the `"__type__"` field.

### Get the type of a polymorphic embed

Sometimes you need to serialize the polymorphic embed and, once in the front-end, need to distinguish them.
`get_polymorphic_type/3` returns the type of the polymorphic embed:

```
PolymorphicEmbed.get_polymorphic_type(Reminder, :channel, SMS) == :sms
```

## Features

* Detect which types to use for the data being `cast`-ed, based on fields present in the data (no need for a *type* field in the data)
* Run changeset validations when a `changeset/2` function is present (when absent, the library will introspect the fields to cast)
* Support for nested polymorphic embeds
* Support for nested `embeds_one`/`embeds_many` embeds
* Display form inputs for polymorphic embeds in Phoenix templates
* Tests to ensure code quality

## Installation

Add `polymorphic_embed` for Elixir as a dependency in your `mix.exs` file:

```elixir
def deps do
  [
    {:polymorphic_embed, "~> 0.14.0"}
  ]
end
```

## HexDocs

HexDocs documentation can be found at [https://hexdocs.pm/polymorphic_embed](https://hexdocs.pm/polymorphic_embed).
