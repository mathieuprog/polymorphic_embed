defmodule PolymorphicEmbed.CustomType do
  @moduledoc false

  defmacro __using__(opts) do
    metadata =
      Keyword.fetch!(opts, :types)
      |> Enum.map(fn
        {type_name, type_opts} when is_list(type_opts) ->
          module = Keyword.fetch!(type_opts, :module)
          identify_by_fields = Keyword.fetch!(type_opts, :identify_by_fields)

          %{
            type: type_name |> to_string(),
            module: module |> Macro.expand(__CALLER__),
            identify_by_fields: identify_by_fields |> Enum.map(&to_string/1)
          }

        {type_name, module} ->
          %{
            type: type_name |> to_string(),
            module: module |> Macro.expand(__CALLER__),
            identify_by_fields: []
          }
      end)

    quote do
      defmodule CustomType do
        defmodule Metadata do
          def get_polymorphic_module(%{"__type__" => type}) do
            unquote(Macro.escape(metadata))
            |> Enum.find(&(type == &1.type))
            |> Map.fetch!(:module)
          end

          def get_polymorphic_module(%{} = attrs) do
            # check if one list is contained in another
            # Enum.count(contained -- container) == 0
            # contained -- container == []
            unquote(Macro.escape(metadata))
            |> Enum.filter(&([] != &1.identify_by_fields))
            |> Enum.find(&([] == &1.identify_by_fields -- Map.keys(attrs)))
            |> case do
              nil ->
                raise "could not infer polymorphic embed from data #{inspect(attrs)}"

              entry ->
                Map.fetch!(entry, :module)
            end
          end

          # Used by form helper `polymorphic_embed_inputs_for/4`.
          # In some cases, the form helper needs to get the module based on a given type in order to build a struct and a
          # changeset for `Phoenix.HTML.Form`.
          def get_polymorphic_module(type) do
            unquote(Macro.escape(metadata))
            |> Enum.find(&(to_string(type) == &1.type))
            |> Map.fetch!(:module)
          end

          def get_polymorphic_type(%module{}), do: get_polymorphic_type(module)

          def get_polymorphic_type(module) do
            unquote(Macro.escape(metadata))
            |> Enum.find(&(module == &1.module))
            |> Map.fetch!(:type)
            |> String.to_atom()
          end
        end

        use Ecto.Type

        def type(), do: :map

        def cast(attrs) do
          # convert keys into string (in case they would be atoms)
          for({key, val} <- attrs, into: %{}, do: {to_string(key), val})
          # get the right module based on the __type__ key or infer from the keys
          |> Metadata.get_polymorphic_module()
          |> cast_to_changeset(attrs)
          |> case do
            %{valid?: true} = changeset ->
              {:ok, Ecto.Changeset.apply_changes(changeset)}

            changeset ->
              {:error, build_errors(changeset)}
          end
        end

        defp cast_to_changeset(%module{} = struct, attrs) do
          if function_exported?(module, :changeset, 2) do
            module.changeset(struct, attrs)
          else
            fields_without_embeds = module.__schema__(:fields) -- module.__schema__(:embeds)

            Ecto.Changeset.cast(struct, attrs, fields_without_embeds)
            |> cast_embeds_to_changeset(module.__schema__(:embeds))
          end
        end

        defp cast_to_changeset(module, attrs) when is_atom(module) do
          cast_to_changeset(struct(module), attrs)
        end

        defp cast_embeds_to_changeset(changeset, embed_fields) do
          Enum.reduce(embed_fields, changeset, fn embed_field, changeset ->
            Ecto.Changeset.cast_embed(
              changeset,
              embed_field,
              with: fn embed_struct, data ->
                cast_to_changeset(embed_struct, data)
              end
            )
          end)
        end

        def load(data) do
          struct =
            data
            |> Metadata.get_polymorphic_module()
            |> cast_to_changeset(data)
            |> Ecto.Changeset.apply_changes()

          {:ok, struct}
        end

        def dump(%_module{} = struct) do
          Ecto.Type.dump(:map, map_from_struct(struct, :polymorphic_embed))
        end

        defp map_from_struct(%module{} = struct, struct_type) do
          Map.from_struct(struct)
          |> maybe_put_type(module, struct_type)
          |> Enum.map(fn {field, value} -> {field, dump_value(field, module, value)} end)
          |> Enum.into(%{})
        end

        defp maybe_put_type(%{} = map, module, :polymorphic_embed) do
          Map.put(map, :__type__, Metadata.get_polymorphic_type(module))
        end

        defp maybe_put_type(%{} = map, _, _), do: map

        defp dump_value(field, parent_module, [value | rest_values]) do
          [
            dump_value(field, parent_module, value)
            | dump_value(field, parent_module, rest_values)
          ]
        end

        defp dump_value(field, parent_module, %_module{} = struct) do
          type = parent_module.__schema__(:type, field)

          case type do
            {:embed, _} ->
              {:ok, term} = Ecto.Type.dump(:map, map_from_struct(struct, :embed))
              term

            _ ->
              # handle nested polymorphic embeds
              if Code.ensure_loaded?(type) and
                   Enum.member?(type.module_info[:attributes][:behaviour], PolymorphicEmbed) do
                {:ok, term} = type.dump(struct)
                term
              else
                struct
              end
          end
        end

        defp dump_value(_, _, value), do: value

        defp build_errors(%{errors: errors, changes: changes} = changeset) do
          Enum.reduce(changes, errors, fn {field, value}, all_errors ->
            case value do
              %Ecto.Changeset{} = changeset ->
                Keyword.merge([{field, {"is invalid", changeset.errors}}], all_errors)

              _ ->
                all_errors
            end
          end)
        end
      end
    end
  end
end
