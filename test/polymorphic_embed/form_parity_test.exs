# Compares the forms that Phoenix builds for embeds_one/embeds_many
# (Phoenix.HTML.FormData, which inputs_for uses) with the forms that
# PolymorphicEmbed.HTML.Helpers builds for polymorphic_embeds_one/many.
#
# Both parents use the same child schema and get the same params. Each test
# takes a snapshot of every form and its nested forms, and asserts that the
# polymorphic snapshot has no differences from the regular one. A failure
# lists each differing path with the regular and the polymorphic value.
#
# The snapshot holds the form contract: what a template reads from a form.
# A valid polymorphic child is a struct, not a changeset. So the action and
# the data of its changeset, and the params of its nested forms, differ from
# Ecto by design, and the snapshot leaves them out. Templates read the data
# of an embed with Ecto.Changeset.get_field/2, so the snapshot compares it
# for each field. The type field is the only other expected difference.
defmodule PolymorphicEmbed.FormParityTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias PolymorphicEmbed.HTML.Helpers

  alias __MODULE__.{Item, Meta, PolyParent, RegularParent, Tag}

  defmodule Meta do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :note, :string
    end

    def changeset(meta, params) do
      meta
      |> cast(params, [:note])
      |> validate_length(:note, min: 3)
    end
  end

  defmodule Tag do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :name, :string
    end

    def changeset(tag, params) do
      tag
      |> cast(params, [:name])
      |> validate_required([:name])
    end
  end

  defmodule Item do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :title, :string
      embeds_one :meta, Meta, on_replace: :update
      embeds_many :tags, Tag, on_replace: :delete
    end

    def changeset(item, params) do
      item
      |> cast(params, [:title])
      |> validate_required([:title])
      |> cast_embed(:meta)
      |> cast_embed(:tags)
    end
  end

  defmodule RegularParent do
    use Ecto.Schema

    embedded_schema do
      embeds_one :item, Item, on_replace: :update
      embeds_many :items, Item, on_replace: :delete
    end
  end

  defmodule PolyParent do
    use Ecto.Schema
    import PolymorphicEmbed

    embedded_schema do
      polymorphic_embeds_one :item, types: [item: Item], on_replace: :update
      polymorphic_embeds_many :items, types: [item: Item], on_replace: :delete
    end
  end

  @type_key "__type__"
  @cast_opts [sort_param: :order, drop_param: :drop]

  ## Scenarios

  # {name, data, field params, parent action}
  # Field params for :items use a map of rows, as an HTML form sends them.
  @scenarios [
    {"new valid row", %{}, %{"title" => "Hello", "_persistent_id" => "p0"}, :validate},
    {"new invalid row", %{}, %{"title" => "", "_persistent_id" => "p0"}, :validate},
    {"new invalid row before submit", %{}, %{"title" => "", "_persistent_id" => "p0"}, nil},
    {"new row with valid nested embeds", %{},
     %{
       "title" => "Hello",
       "meta" => %{"note" => "a note"},
       "tags" => %{"0" => %{"name" => "a"}, "1" => %{"name" => "b"}}
     }, :validate},
    {"new row with invalid nested embeds", %{},
     %{
       "title" => "Hello",
       "meta" => %{"note" => "x"},
       "tags" => %{"0" => %{"name" => ""}}
     }, :validate},
    {"existing data without params", :existing, nil, nil},
    {"existing data updated by id", :existing,
     %{
       "id" => "i1",
       "title" => "New",
       "meta" => %{"id" => "m1", "note" => "new note"},
       "tags" => %{"0" => %{"id" => "t1", "name" => "new tag"}}
     }, :validate}
  ]

  for {name, data, field_params, action} <- @scenarios do
    test "embeds_one: #{name}" do
      data = data(unquote(Macro.escape(data)), :one)
      params = params(:item, unquote(Macro.escape(field_params)))
      assert_parity(data, params, :item, unquote(action))
    end

    test "embeds_many: #{name}" do
      data = data(unquote(Macro.escape(data)), :many)
      params = params(:items, unquote(Macro.escape(field_params)))
      assert_parity(data, params, :items, unquote(action))
    end
  end

  test "embeds_one: no data and no params" do
    assert_parity(%{}, %{}, :item, nil, polymorphic_type: :item)
  end

  test "embeds_many: two rows with list params" do
    params = %{
      "items" => [
        %{"title" => "One", "_persistent_id" => "p0"},
        %{"title" => "", "_persistent_id" => "p1"}
      ]
    }

    assert_parity(%{}, params, :items, :validate)
  end

  test "embeds_many: sort and drop" do
    params = %{
      "items" => %{
        "0" => %{"title" => "Zero", "_persistent_id" => "p0"},
        "1" => %{"title" => "", "_persistent_id" => "p1"},
        "2" => %{"title" => "Two", "_persistent_id" => "p2"}
      },
      "order" => ["2", "1", "0", "new"],
      "drop" => ["0"]
    }

    assert_parity(%{}, params, :items, :validate)
  end

  test "embeds_many: sort and drop on existing data" do
    params = %{
      "items" => %{
        "0" => %{"id" => "i1", "title" => "Old"},
        "1" => %{"id" => "i2", "title" => "Other"}
      },
      "order" => ["1", "0"],
      "drop" => ["1"]
    }

    assert_parity(data(:existing, :many), params, :items, :validate)
  end

  ## Helpers

  defp data(:existing, :one), do: %{item: existing_item()}
  defp data(:existing, :many), do: %{items: [existing_item(), existing_item2()]}
  defp data(%{} = data, _), do: data

  defp existing_item do
    %Item{
      id: "i1",
      title: "Old",
      meta: %Meta{id: "m1", note: "old note"},
      tags: [%Tag{id: "t1", name: "old tag"}]
    }
  end

  defp existing_item2, do: %Item{id: "i2", title: "Other", meta: nil, tags: []}

  defp params(_field, nil), do: %{}
  defp params(:item, row), do: %{"item" => row}
  defp params(:items, row), do: %{"items" => %{"0" => row}}

  defp assert_parity(data, params, field, action, poly_opts \\ []) do
    regular =
      struct(RegularParent, data)
      |> Changeset.cast(params, [])
      |> Changeset.cast_embed(field, @cast_opts)
      |> Map.put(:action, action)

    poly =
      struct(PolyParent, data)
      |> Changeset.cast(add_type(params, field), [])
      |> PolymorphicEmbed.cast_polymorphic_embed(field, @cast_opts)
      |> Map.put(:action, action)

    regular_forms =
      Phoenix.HTML.FormData.to_form(
        regular,
        Phoenix.Component.to_form(regular, as: "parent"),
        field,
        []
      )

    poly_forms =
      Helpers.to_form(poly, Phoenix.Component.to_form(poly, as: "parent"), field, poly_opts)

    assert diff(snapshot_forms(regular_forms), snapshot_forms(poly_forms), [field]) == []
  end

  defp add_type(params, :item) do
    case params do
      %{"item" => %{} = row} -> %{params | "item" => Map.put(row, @type_key, "item")}
      params -> params
    end
  end

  defp add_type(params, :items) do
    case params do
      %{"items" => rows} when is_list(rows) ->
        %{params | "items" => Enum.map(rows, &Map.put(&1, @type_key, "item"))}

      %{"items" => rows} ->
        %{params | "items" => Map.new(rows, fn {k, v} -> {k, Map.put(v, @type_key, "item")} end)}

      params ->
        params
    end
  end

  # A snapshot holds the form contract. Nested forms have no params in it.
  defp snapshot_forms(forms, nested? \\ false), do: Enum.map(forms, &snapshot_form(&1, nested?))

  defp snapshot_form(%Phoenix.HTML.Form{} = form, nested?) do
    module = form.source.data.__struct__
    embeds = module.__schema__(:embeds)
    fields = module.__schema__(:fields)

    snapshot = %{
      id: form.id,
      name: form.name,
      index: form.index,
      action: form.action,
      errors: form.errors,
      hidden: Keyword.delete(form.hidden, String.to_atom(@type_key)) |> drop_type_hidden(),
      values: Map.new(fields -- embeds, &{&1, normalize(form[&1].value)}),
      fields: Map.new(fields, &{&1, normalize(Changeset.get_field(form.source, &1))}),
      nested:
        Map.new(embeds, fn embed ->
          nested_forms = Phoenix.HTML.FormData.to_form(form.source, form, embed, [])
          {embed, snapshot_forms(nested_forms, true)}
        end)
    }

    if nested?, do: snapshot, else: Map.put(snapshot, :params, drop_type(form.params))
  end

  defp drop_type(params) when is_map(params), do: Map.delete(params, @type_key)
  defp drop_type(params), do: params

  defp drop_type_hidden(hidden),
    do: Enum.reject(hidden, fn {key, _} -> to_string(key) == @type_key end)

  # Shows a value by its kind, so a diff tells a changeset, a struct and raw
  # params apart. Generated UUIDs are replaced, so that runs are stable.
  defp normalize(%Changeset{} = changeset) do
    {:changeset,
     %{
       action: changeset.action,
       changes: normalize(changeset.changes),
       errors: changeset.errors,
       valid?: changeset.valid?
     }}
  end

  defp normalize(%_{} = struct) do
    {:struct, struct.__struct__,
     struct |> Map.from_struct() |> Map.delete(:__meta__) |> normalize()}
  end

  defp normalize(%{} = map), do: Map.new(map, fn {k, v} -> {k, normalize(v)} end)
  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)

  defp normalize(value) when is_binary(value) do
    if Regex.match?(~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, value),
      do: "<generated uuid>",
      else: value
  end

  defp normalize(value), do: value

  # Returns a list of {path, regular, polymorphic} for each leaf that differs.
  defp diff(same, same, _path), do: []

  # The cast generates the id of a new child at once. Ecto generates it on
  # insert, so its form shows nil.
  defp diff(nil, "<generated uuid>", _path), do: []

  defp diff(%{} = regular, %{} = poly, path)
       when not is_struct(regular) and not is_struct(poly) do
    (Map.keys(regular) ++ Map.keys(poly))
    |> Enum.uniq()
    |> Enum.flat_map(
      &diff(Map.get(regular, &1, :missing), Map.get(poly, &1, :missing), path ++ [&1])
    )
  end

  defp diff(regular, poly, path)
       when is_list(regular) and is_list(poly) and length(regular) == length(poly) and
              path != [] do
    if Keyword.keyword?(regular) and regular != [] do
      [{Enum.join(path, "."), regular, poly}]
    else
      regular
      |> Enum.zip(poly)
      |> Enum.with_index()
      |> Enum.flat_map(fn {{r, p}, i} -> diff(r, p, path ++ [i]) end)
    end
  end

  defp diff(regular, poly, path), do: [{Enum.join(path, "."), regular, poly}]
end
