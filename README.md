# Polymorphic embeds for Ecto

`polymorphic_embed` brings support for polymorphic/dynamic embedded schemas in Ecto.

Ecto's `embeds_one` and `embeds_many` macros require a specific schema module to be specified. This library removes this restriction by
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
  import PolymorphicEmbed

  schema "reminders" do
    field :date, :utc_datetime
    field :text, :string

    polymorphic_embeds_one :channel,
      types: [
        sms: MyApp.Channel.SMS,
        email: MyApp.Channel.Email
      ],
      on_type_not_found: :raise,
      on_replace: :update
  end

  def changeset(struct, values) do
    struct
    |> cast(values, [:date, :text])
    |> cast_polymorphic_embed(:channel, required: true)
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
    |> cast(params, [:address, :confirmed])
    |> validate_required(:address)
    |> validate_length(:address, min: 4)
  end
end
```

```elixir
defmodule MyApp.Channel.SMS do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :number, :string
  end

  def changeset(sms, params) do
    sms
    |> cast(params, [:number])
    |> validate_required(:number)
  end
end
```

In your migration file, you may use the type `:map` for both `polymorphic_embeds_one/2` and `polymorphic_embeds_many/2` fields.

```elixir
add(:channel, :map)
```

[It is not recommended](https://hexdocs.pm/ecto/3.11.2/Ecto.Schema.html#embeds_many/3) to use `{:array, :map}` for a list of embeds.

### `cast_polymorphic_embed/3`

`cast_polymorphic_embed/3` must be called to cast the polymorphic embed's parameters.

#### Options

* `:required` – if the embed is a required field.

* `:with` – allows you to specify a custom changeset.
```elixir
changeset
|> cast_polymorphic_embed(:channel,
  with: [
    sms: &SMS.custom_changeset/2,
    email: &Email.custom_changeset/2
  ]
)
```

* `:drop_param` – see [sorting-and-deleting-from-many-collections](https://hexdocs.pm/ecto/3.11.2/Ecto.Changeset.html#cast_assoc/3-sorting-and-deleting-from-many-collections).

* `:sort_param` – see [sorting-and-deleting-from-many-collections](https://hexdocs.pm/ecto/3.11.2/Ecto.Changeset.html#cast_assoc/3-sorting-and-deleting-from-many-collections).

* `:default_type_on_sort_create` – in some cases, [`sort` creates a new entry](https://github.com/elixir-ecto/ecto/blob/v3.11/test/ecto/changeset/embedded_test.exs#L464); this option specifies which type to use by default for the entry.

### PolymorphicEmbed Ecto type

The `:types` option for the `PolymorphicEmbed` custom type contains a keyword list mapping an atom representing the type
(in this example `:email` and `:sms`) with the corresponding embedded schema module.

There are two strategies to detect the right embedded schema to use:

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

#### List of polymorphic embeds

Lists of polymorphic embeds are also supported:

```elixir
polymorphic_embeds_many :contexts,
  types: [
    location: MyApp.Context.Location,
    age: MyApp.Context.Age,
    device: MyApp.Context.Device
  ],
  on_replace: :delete,
  on_type_not_found: :raise,
  nilify_unlisted_types_on_load: [:deprecated_type]
```

#### Options

* `:types` – discussed above.
* `:type_field_name` – specify a custom type field. Defaults to `:__type__`.
* `:on_type_not_found` – specify what to do if the embed's type cannot be inferred.
  Possible values are
  - `:raise`: raise an error
  - `:changeset_error`: add a changeset error
  - `:nilify`: replace the data by `nil`; only for single (non-list) embeds
  - `:ignore`: ignore the data; only for lists of embeds

  By default, a changeset error "is invalid" is added.
* `:on_replace` – mandatory option that can only be set to `:update` for a single embed and `:delete` for a list of
  embeds (we force a value as the default value of this option for `embeds_one` and `embeds_many` is `:raise`).
* `:retain_unlisted_types_on_load`: allow unconfigured types to be loaded without raising an error. Useful for handling deprecated structs still present in the database.
* `:nilify_unlisted_types_on_load`: same as `:retain_unlisted_types_on_load`, but nilify the struct on load.

### Displaying form inputs and errors in Phoenix templates

The library comes with a form helper in order to build form inputs for polymorphic embeds and display changeset errors.

In the entrypoint defining your web interface (`lib/your_app_web.ex` file), add the following import, change `view` to the one your component use:

```elixir
def view do
  quote do
    # imports and stuff
    import PolymorphicEmbed.HTML.Form
  end
end
```

This provides you with the `polymorphic_embed_inputs_for/3` and `polymorphic_embed_inputs_for/4` functions.

Here is an example form using the imported function:

```elixir
<%= inputs_for f, :reminders, fn reminder_form -> %>
  <%= polymorphic_embed_inputs_for reminder_form, :channel, :sms, fn sms_form -> %>
    <div class="sms-inputs">
      <label>Number</label>
      <%= text_input sms_form, :number %>
      <div class="error">
        <%= error_tag sms_form, :number %>
      </div>
    </div>
  <% end %>
<% end %>
```

When using `polymorphic_embed_inputs_for/4`, you have to manually specify the type. When the embed is `nil`, empty fields will be displayed.

`polymorphic_embed_inputs_for/3` doesn't require the type to be specified. When the embed is `nil`, no fields are displayed.

They both render a hidden input for the `"__type__"` field.

### Displaying form inputs and errors in LiveView

You may use `PolymorphicEmbed.HTML.Component.polymorphic_embed_inputs_for/1` when working with LiveView, which functions similarly to [`Phoenix.Component.inputs_for/1`](Phoenix.Component.inputs_for).

```elixir
<.form
  :let={f}
  for={@changeset}
  id="reminder-form"
  phx-change="validate"
  phx-submit="save"
>
  <.polymorphic_embed_inputs_for field={f[:channel]} :let={channel_form}>
    <%= case source_module(channel_form) do %>
      <% SMS -> %>
        <.input field={channel_form[:number]} label="Number" />

      <% Email -> %>
        <.input field={channel_form[:address]} label="Email Address" />
    <% end %>
  </.polymorphic_embed_inputs_for>
</.form>
```

### Get the type and module of a polymorphic embed

Sometimes you need to serialize the polymorphic embed and, once in the front-end, need to distinguish them.
`PolymorphicEmbed.get_polymorphic_type/3` returns the type of the polymorphic embed:

```elixir
PolymorphicEmbed.get_polymorphic_type(Reminder, :channel, SMS) == :sms
```

To get the module for a specific type, use:

```elixir
PolymorphicEmbed.get_polymorphic_module(Reminder, :channel, :sms) == SMS
```

### `traverse_errors/2`

The function `Ecto.changeset.traverse_errors/2` won't include the errors of polymorphic embeds. You may instead use `PolymorphicEmbed.traverse_errors/2` when working with polymorphic embeds.

## Installation

Add `polymorphic_embed` for Elixir as a dependency in your `mix.exs` file:

```elixir
def deps do
  [
    {:polymorphic_embed, "~> 4.1.1"}
  ]
end
```

## HexDocs

HexDocs documentation can be found at [https://hexdocs.pm/polymorphic_embed](https://hexdocs.pm/polymorphic_embed).
