# Polymorphic embeds for Ecto

`polymorphic_embed` brings support for polymorphic/dynamic embedded schemas in Ecto.

Ecto's `embeds_one` macro requires a specific schema module to be specified. This library removes this restriction by
**dynamically** determining which schema to use, based on data to be stored (from a form or API) and retrieved (from the
data source).


## Usage

#### Enable polymorphism

Let's say we want a schema `Reminder`, that can be sent either by email or by SMS.

We create the `Email` and `SMS` embedded schemas containing the fields that are specific for each of those communication
channels.

The `Reminder` schema can then contain a `:channel` field that will either hold an `Email` or `SMS` struct, by setting
its type to the custom type that this library provides.

Find the schema code and explanations below.

```elixir
defmodule MyApp.Reminder do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reminders" do
    field :date, :utc_datetime
    field :text, :string
    field :channel, MyApp.ChannelData
  end

  def changeset(struct, values) do
    struct
    |> cast(values, [:date, :text, :channel])
    |> validate_required(:date)
  end
end
```

```elixir
defmodule MyApp.ChannelData do
  use PolymorphicEmbed, types: [
    sms: MyApp.Channel.SMS,
    email: [module: MyApp.Channel.Email, identify_by_fields: [:address, :confirmed]]
  ]
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

You have noticed in the code above that you need to define an intermediary module, in this example `ChannelData`. This
module is the Ecto Type (through `use`-ing `PolymorphicEmbed`).

The `:types` option for `PolymorphicEmbed` contains a keyword list mapping an atom representing the type (in this
example `:email` and `:sms`) with the corresponding embedded schema module.

Two styles of such mapping have been shown in the code above:

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

Here we specify how the type can be determined based on the presence of given fields. If the data contains `:address`
and `:confirmed` parameters (or their string version), the type is `:email`. A `"__type__"` parameter is then no longer
required.

#### Displaying form inputs and errors

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

## Installation

Add `polymorphic_embed` for Elixir as a dependency in your `mix.exs` file:

```elixir
def deps do
  [
    {:polymorphic_embed, "~> 0.1.0"}
  ]
end
```

## HexDocs

HexDocs documentation can be found at [https://hexdocs.pm/polymorphic_embed](https://hexdocs.pm/polymorphic_embed).
