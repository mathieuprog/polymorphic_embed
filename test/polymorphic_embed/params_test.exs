defmodule PolymorphicEmbed.ParamsTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset

  defmodule Part do
    use Ecto.Schema

    embedded_schema do
      field(:body, :string)
    end

    def changeset(data, params), do: Changeset.cast(data, params, [:body])
  end

  defmodule Story do
    use Ecto.Schema

    embedded_schema do
      field(:title, :string)
      field(:media_file, :map, virtual: true)
      field(:payload, :map)
      embeds_many(:parts, Part, on_replace: :delete)
    end

    def changeset(data, params) do
      data
      |> Changeset.cast(params, [:title, :payload])
      |> Changeset.validate_required(:title)
      |> Changeset.cast_embed(:parts)
    end
  end

  defmodule Other do
    use Ecto.Schema

    embedded_schema do
      field(:title, :string)
      field(:media_file, :map, virtual: true)
    end

    def changeset(data, params), do: Changeset.cast(data, params, [:title])
  end

  defmodule RestrictedStory do
    use Ecto.Schema

    embedded_schema do
      embeds_many(:parts, Part)
    end

    def changeset(data, params) do
      data
      |> Changeset.cast(params, [])
      |> Changeset.cast_embed(:parts)
    end
  end

  defmodule Content do
    use Ecto.Schema
    import PolymorphicEmbed

    embedded_schema do
      polymorphic_embeds_many(:children,
        types: [story: Story, other: Other, restricted: RestrictedStory],
        on_replace: :delete
      )

      polymorphic_embeds_one(:featured,
        types: [story: Story],
        type_field_name: :kind,
        on_replace: :update
      )
    end
  end

  for key_type <- [:atoms, :strings], shape <- [:list, :indexed] do
    test "preserves existing data with #{key_type} as parameter keys in a #{shape}" do
      existing = story()
      row = %{__type__: "story", id: existing.id, title: "updated"}
      row = if unquote(key_type) == :strings, do: stringify(row), else: row
      rows = if unquote(shape) == :list, do: [row], else: %{"0" => row}

      changeset = cast(%Content{children: [existing]}, %{children: rows}, :children)

      assert [%Story{} = child] = changeset.changes.children
      assert child.id == existing.id
      assert child.media_file == existing.media_file
      assert child.title == "updated"
    end
  end

  for key_type <- [:atoms, :strings] do
    test "passes normalized parameters and existing data to with callbacks for #{key_type} keys" do
      existing = story()
      payload = %{keep_atom_key: %{nested: "unchanged"}}
      row = %{__type__: "story", id: existing.id, title: "updated", payload: payload}
      expected = stringify(row)
      row = if unquote(key_type) == :strings, do: expected, else: row

      callback = fn data, params ->
        assert data == existing
        assert params == expected
        Story.changeset(data, params)
      end

      changeset =
        cast(%Content{children: [existing]}, %{children: [row]}, :children,
          with: [story: callback]
        )

      assert [child] = changeset.changes.children
      assert child.payload == payload
      assert child.media_file == existing.media_file
    end
  end

  test "retains the existing child and update action when validation fails" do
    existing = story()

    changeset =
      cast(
        %Content{children: [existing]},
        %{"children" => [%{"__type__" => "story", "id" => existing.id, "title" => ""}]},
        :children
      )

    assert [%Changeset{} = child] = changeset.changes.children
    assert child.data == existing
    assert child.action == :update
    refute child.valid?
    assert Keyword.has_key?(child.errors, :title)
  end

  test "normalizes single embed parameters before a custom changeset function" do
    existing = story()
    row = %{kind: "story", id: existing.id, title: "updated"}

    callback = fn data, params ->
      assert data == existing
      assert params == stringify(row)
      Story.changeset(data, params)
    end

    changeset =
      cast(%Content{featured: existing}, %{featured: row}, :featured, with: [story: callback])

    assert changeset.changes.featured.media_file == existing.media_file
    assert changeset.changes.featured.title == "updated"
  end

  test "normalizes rows created by sort before the changeset callback" do
    callback = fn data, params ->
      assert params == %{"__type__" => :story}
      Story.changeset(data, params)
    end

    changeset =
      cast(%Content{}, %{order: ["new"]}, :children,
        sort_param: :order,
        default_type_on_sort_create: :story,
        with: [story: callback]
      )

    assert [%Changeset{action: :insert}] = changeset.changes.children
  end

  for field <- [:children, :featured],
      row <- [
        %{"__type__" => "story", "kind" => "story", title: "mixed"},
        %{"__type__" => "story", "kind" => "story", "id" => "one", id: "two"},
        %{"__type__" => "story", "kind" => "story", 1 => "invalid key"}
      ] do
    test "rejects invalid parameter keys for #{field}: #{inspect(row)}" do
      row = unquote(Macro.escape(row))
      value = if unquote(field) == :children, do: [row], else: row

      callback = fn _data, _params ->
        flunk("Invalid keys must not reach the changeset callback")
      end

      assert_raise Ecto.CastError, fn ->
        cast(%Content{}, %{unquote(field) => value}, unquote(field), with: [story: callback])
      end
    end
  end

  test "requires both ID and module to match an existing child" do
    existing = story()

    changeset =
      cast(
        %Content{children: [existing]},
        %{"children" => [%{"__type__" => "other", "id" => existing.id, "title" => "new"}]},
        :children
      )

    assert [%Other{media_file: nil, title: "new"}] = changeset.changes.children
  end

  test "does not match existing children without an ID" do
    existing = %{story() | id: nil}

    changeset =
      cast(
        %Content{children: [existing]},
        %{children: [%{__type__: "story", title: "new"}]},
        :children
      )

    assert [%Story{media_file: nil} = child] = changeset.changes.children
    assert child.id
  end

  test "preserves child data through sorting and dropping" do
    first = story()
    second = %{story() | media_file: %{path: "second-file"}}
    dropped = story()

    params = %{
      "children" => %{
        "0" => %{"__type__" => "story", "id" => first.id, "title" => "first"},
        "1" => %{"__type__" => "story", "id" => second.id, "title" => "second"},
        "2" => %{"__type__" => "story", "id" => dropped.id, "title" => "dropped"}
      },
      "order" => ["1", "2", "0"],
      "remove" => ["2"]
    }

    changeset =
      cast(%Content{children: [first, second, dropped]}, params, :children,
        sort_param: :order,
        drop_param: :remove
      )

    assert Enum.map(changeset.changes.children, &{&1.id, &1.media_file}) == [
             {second.id, second.media_file},
             {first.id, first.media_file}
           ]
  end

  test "updates, reorders and removes nested embeds on existing data" do
    first = %Part{id: Ecto.UUID.generate(), body: "first"}
    second = %Part{id: Ecto.UUID.generate(), body: "second"}
    dropped = %Part{id: Ecto.UUID.generate(), body: "dropped"}
    existing = %{story() | parts: [first, second, dropped]}

    params = %{
      "children" => [
        %{
          "__type__" => "story",
          "id" => existing.id,
          "parts" => [%{"id" => second.id, "body" => "updated"}, %{"id" => first.id}]
        }
      ]
    }

    changeset = cast(%Content{children: [existing]}, params, :children)
    assert [%Story{} = child] = changeset.changes.children
    assert child.media_file == existing.media_file

    assert Enum.map(child.parts, &{&1.id, &1.body}) == [
             {second.id, "updated"},
             {first.id, "first"}
           ]
  end

  test "honors nested on_replace restrictions on existing data" do
    existing = %RestrictedStory{
      id: Ecto.UUID.generate(),
      parts: [%Part{id: Ecto.UUID.generate(), body: "kept"}]
    }

    params = %{
      "children" => [%{"__type__" => "restricted", "id" => existing.id, "parts" => []}]
    }

    assert_raise RuntimeError, ~r/on_replace/, fn ->
      cast(%Content{children: [existing]}, params, :children)
    end
  end

  defp story do
    %Story{id: Ecto.UUID.generate(), title: "original", media_file: %{path: "existing-file"}}
  end

  defp stringify(params), do: Map.new(params, fn {key, value} -> {Atom.to_string(key), value} end)

  defp cast(data, params, field, options \\ []) do
    data
    |> Changeset.cast(params, [])
    |> PolymorphicEmbed.cast_polymorphic_embed(field, options)
  end
end
