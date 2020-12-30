defmodule PolymorphicEmbed do
  use Ecto.ParameterizedType

  @impl true
  def type(_params), do: :map

  @impl true
  def init(opts) do
    if Keyword.get(opts, :on_replace) not in [:update, :delete] do
      raise("`:on_replace` option for polymorphic embed must be set to `:update` (single embed) or `:delete` (list of embeds)")
    end

    types_metadata =
      Keyword.fetch!(opts, :types)
      |> Enum.map(fn
        {type_name, type_opts} when is_list(type_opts) ->
          {type_name, type_opts}

        {type_name, module} ->
          {type_name, module: module}
      end)
      |> Enum.map(fn
        {type_name, type_opts} when is_list(type_opts) ->
          %{
            type: type_name |> to_string(),
            module: Keyword.fetch!(type_opts, :module),
            identify_by_fields: Keyword.get(type_opts, :identify_by_fields, []) |> Enum.map(&to_string/1)
          }
      end)

    %{
      types_metadata: types_metadata,
      on_type_not_found: Keyword.get(opts, :on_type_not_found, :changeset_error),
      type_field: Keyword.get(opts, :type_field, :__type__) |> to_string(),
      on_replace: Keyword.fetch!(opts, :on_replace)
    }
  end

  def cast_polymorphic_embed(changeset, field, cast_options \\ []) do
    field_options = get_field_options(changeset.data.__struct__, field)

    %{array?: array?, on_replace: on_replace} = field_options

    if array? and on_replace != :delete do
      raise "`:on_replace` option for field #{inspect field} must be set to `:update`"
    end

    if not array? and on_replace != :update do
      raise "`:on_replace` option for field #{inspect field} must be set to `:delete`"
    end

    required = Keyword.get(cast_options, :required, false)

    changeset.params
    |> Map.fetch(to_string(field))
    |> case do
      :error when required ->
        if Map.fetch!(changeset.data, field) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, field, "can't be blank", validation: :required)
        end

      :error when not required ->
        changeset

      {:ok, nil} when required ->
        Ecto.Changeset.add_error(changeset, field, "can't be blank", validation: :required)

      {:ok, nil} when not required ->
        Ecto.Changeset.put_change(changeset, field, nil)

      {:ok, map} when map == %{} and not array? ->
        changeset

      {:ok, params_for_field} ->
        cond do
          array? and is_list(params_for_field) ->
            cast_polymorphic_embeds_many(changeset, field, params_for_field, field_options)

          not array? and is_map(params_for_field) ->
            cast_polymorphic_embeds_one(changeset, field, params_for_field, field_options)
        end
    end
  end

  defp cast_polymorphic_embeds_one(changeset, field, params, field_options) do
    %{types_metadata: types_metadata, on_type_not_found: on_type_not_found, type_field: type_field} = field_options

    data_for_field = Map.fetch!(changeset.data, field)

    struct =
      # We support partial update of the embed. If the type cannot be inferred from the parameters, or if the found type
      # hasn't changed, pass the data to the changeset.
      case do_get_polymorphic_module_from_map(params, type_field, types_metadata) do
        nil ->
          if data_for_field do
            data_for_field
          else
            :type_not_found
          end

        module when is_nil(data_for_field) ->
          struct(module)

        module ->
          if data_for_field.__struct__ != module do
            struct(module)
          else
            data_for_field
          end
      end

    case struct do
      :type_not_found when on_type_not_found == :raise ->
        raise_cannot_infer_type_from_data(params)

      :type_not_found when on_type_not_found == :changeset_error ->
        Ecto.Changeset.add_error(changeset, field, "is invalid")

      struct ->
        embed_changeset = struct.__struct__.changeset(struct, params)

        embed_changeset = %{embed_changeset | action: if(data_for_field, do: :update, else: :insert)}

        case embed_changeset do
           %{valid?: true} = embed_changeset ->
             Ecto.Changeset.put_change(
               changeset,
               field,
               Ecto.Changeset.apply_changes(embed_changeset)
             )

           %{valid?: false} = embed_changeset ->
             changeset
             |> Ecto.Changeset.put_change(field, embed_changeset)
             |> Map.put(:valid?, false)
         end
    end
  end

  defp cast_polymorphic_embeds_many(changeset, field, list_params, field_options) do
    %{types_metadata: types_metadata, on_type_not_found: on_type_not_found, type_field: type_field} = field_options

    embeds =
      Enum.map(list_params, fn params ->
        case do_get_polymorphic_module_from_map(params, type_field, types_metadata) do
          nil when on_type_not_found == :raise ->
            raise_cannot_infer_type_from_data(params)

          nil when on_type_not_found == :changeset_error ->
           :error

          module ->
            embed_changeset = module.changeset(struct(module), params)

            embed_changeset = %{embed_changeset | action: :insert}

            case embed_changeset do
               %{valid?: true} = embed_changeset ->
                 Ecto.Changeset.apply_changes(embed_changeset)

               %{valid?: false} = embed_changeset ->
                 embed_changeset
             end
        end
      end)

    if Enum.any?(embeds, &(&1 == :error)) do
      Ecto.Changeset.add_error(changeset, field, "is invalid")
    else
      any_invalid? = Enum.any?(embeds, fn
        %{valid?: false} -> true
        _ -> false
      end)

      Ecto.Changeset.put_change(changeset, field, embeds)
      |> Map.put(:valid?, !any_invalid?)
    end
  end

  @impl true
  def cast(_data, _params),
    do:
      raise(
        "#{__MODULE__} must not be casted using Ecto.Changeset.cast/4, use #{__MODULE__}.cast_polymorphic_embed/2 instead."
      )

  @impl true
  def embed_as(_format, _params), do: :dump

  @impl true
  def load(nil, _loader, _params), do: {:ok, nil}

  def load(data, _loader, %{types_metadata: types_metadata, type_field: type_field}) do
    case do_get_polymorphic_module_from_map(data, type_field, types_metadata) do
      nil -> raise_cannot_infer_type_from_data(data)
      module when is_atom(module) -> {:ok, Ecto.embedded_load(module, data, :json)}
    end
  end

  @impl true
  def dump(%Ecto.Changeset{valid?: false}, _dumper, _params) do
    raise "cannot dump invalid changeset"
  end

  def dump(%module{} = struct, dumper, %{types_metadata: types_metadata, type_field: type_field}) do
    map =
      struct
      |> map_from_struct()
      |> Map.put(type_field, do_get_polymorphic_type(module, types_metadata))

    dumper.(:map, map)
  end

  def dump(nil, dumper, _params), do: dumper.(:map, nil)

  defp map_from_struct(struct) do
    Ecto.embedded_dump(struct, :json)
  end

  def get_polymorphic_module(schema, field, type_or_data) do
    %{types_metadata: types_metadata, type_field: type_field} = get_field_options(schema, field)

    case type_or_data do
      map when is_map(map) -> do_get_polymorphic_module_from_map(map, type_field, types_metadata)
      type when is_atom(type) or is_binary(type) -> do_get_polymorphic_module_for_type(type, types_metadata)
    end
  end

  defp do_get_polymorphic_module_from_map(%{} = attrs, type_field, types_metadata) do
    attrs = attrs |> convert_map_keys_to_string()

    type = Enum.find_value(attrs, fn {key, value} -> key == type_field && value end)

    if type do
      do_get_polymorphic_module_for_type(type, types_metadata)
    else
      # check if one list is contained in another
      # Enum.count(contained -- container) == 0
      # contained -- container == []
      types_metadata
      |> Enum.filter(&([] != &1.identify_by_fields))
      |> Enum.find(&([] == &1.identify_by_fields -- Map.keys(attrs)))
      |> (&(&1 && Map.fetch!(&1, :module))).()
    end
  end

  defp do_get_polymorphic_module_for_type(type, types_metadata) do
    get_metadata_for_type(type, types_metadata)
    |> (&(&1 && Map.fetch!(&1, :module))).()
  end

  def get_polymorphic_type(schema, field, module_or_struct) do
    %{types_metadata: types_metadata} = get_field_options(schema, field)
    do_get_polymorphic_type(module_or_struct, types_metadata)
  end

  defp do_get_polymorphic_type(%module{}, types_metadata),
    do: do_get_polymorphic_type(module, types_metadata)

  defp do_get_polymorphic_type(module, types_metadata) do
    get_metadata_for_module(module, types_metadata)
    |> Map.fetch!(:type)
    |> String.to_atom()
  end

  defp get_metadata_for_module(module, types_metadata) do
    Enum.find(types_metadata, &(module == &1.module))
  end

  defp get_metadata_for_type(type, types_metadata) do
    type = to_string(type)
    Enum.find(types_metadata, &(type == &1.type))
  end

  defp get_field_options(schema, field) do
    try do
      schema.__schema__(:type, field)
    rescue
      _ in UndefinedFunctionError ->
        raise ArgumentError, "#{inspect(schema)} is not an Ecto schema"
    else
      {:parameterized, PolymorphicEmbed, options} -> Map.put(options, :array?, false)
      {:array, {:parameterized, PolymorphicEmbed, options}} -> Map.put(options, :array?, true)
      {_, {:parameterized, PolymorphicEmbed, options}} -> Map.put(options, :array?, false)
      nil -> raise ArgumentError, "#{field} is not an Ecto.Enum field"
    end
  end

  defp convert_map_keys_to_string(%{} = map),
    do: for({key, val} <- map, into: %{}, do: {to_string(key), val})

  defp raise_cannot_infer_type_from_data(data),
    do: raise("could not infer polymorphic embed from data #{inspect(data)}")
end
