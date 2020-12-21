defmodule PolymorphicEmbed do
  use Ecto.ParameterizedType

  @impl true
  def type(_params), do: :map

  @impl true
  def init(opts) do
    metadata =
      Keyword.fetch!(opts, :types)
      |> Enum.map(fn
        {type_name, type_opts} when is_list(type_opts) ->
          module = Keyword.fetch!(type_opts, :module)
          identify_by_fields = Keyword.fetch!(type_opts, :identify_by_fields)

          %{
            type: type_name |> to_string(),
            module: module,
            identify_by_fields: identify_by_fields |> Enum.map(&to_string/1)
          }

        {type_name, module} ->
          %{
            type: type_name |> to_string(),
            module: module,
            identify_by_fields: []
          }
      end)

    %{
      metadata: metadata,
      on_type_not_found: Keyword.get(opts, :on_type_not_found, :changeset_error)
    }
  end

  def cast_polymorphic_embed(changeset, field) do
    %{metadata: metadata, on_type_not_found: on_type_not_found} =
      get_options(changeset.data.__struct__, field)

    changeset.params
    |> Map.fetch(to_string(field))
    |> case do
      :error ->
        changeset

      {:ok, nil} ->
        Ecto.Changeset.put_change(changeset, field, nil)

      {:ok, params_for_field} ->
        params =
          Map.fetch!(changeset.data, field)
          |> case do
            nil -> %{}
            struct -> map_from_struct(struct, metadata)
          end
          |> Map.merge(params_for_field || %{})
          |> convert_map_keys_to_string()

        case do_get_polymorphic_module(params, metadata) do
          nil when on_type_not_found == :raise ->
            raise_cannot_infer_type_from_data(params)

          nil when on_type_not_found == :changeset_error ->
            Ecto.Changeset.add_error(changeset, field, "is invalid")

          module ->
            module
            |> struct()
            |> cast_to_changeset(params)
            |> case do
              %{valid?: true} = embed_changeset ->
                Ecto.Changeset.put_change(
                  changeset,
                  field,
                  Ecto.Changeset.apply_changes(embed_changeset)
                )

              %{valid?: false} = embed_changeset ->
                changeset
                |> Ecto.Changeset.put_change(field, Ecto.Changeset.apply_changes(embed_changeset))
                |> Ecto.Changeset.add_error(field, "is invalid", embed_changeset.errors)
            end
        end
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

  defp cast_to_changeset(%module{} = struct, attrs) do
    if function_exported?(module, :changeset, 2) do
      module.changeset(struct, attrs)
    else
      Ecto.Changeset.cast(struct, attrs, module.__schema__(:fields))
    end
  end

  @impl true
  def load(nil, _loader, _params), do: {:ok, nil}

  def load(data, _loader, %{metadata: metadata}) do
    case do_get_polymorphic_module(data, metadata) do
      nil -> raise_cannot_infer_type_from_data(data)
      module when is_atom(module) -> {:ok, Ecto.embedded_load(module, data, :json)}
    end
  end

  @impl true
  def dump(%_module{} = struct, dumper, %{metadata: metadata}) do
    dumper.(:map, map_from_struct(struct, metadata))
  end

  def dump(nil, dumper, _params) do
    dumper.(:map, nil)
  end

  defp map_from_struct(%module{} = struct, metadata) do
    struct
    |> Ecto.embedded_dump(:json)
    |> Map.put(:__type__, do_get_polymorphic_type(module, metadata))
  end

  def get_polymorphic_module(schema, field, type_or_data) do
    %{metadata: metadata} = get_options(schema, field)
    do_get_polymorphic_module(type_or_data, metadata)
  end

  defp do_get_polymorphic_module(%{:__type__ => type}, metadata),
    do: do_get_polymorphic_module(type, metadata)

  defp do_get_polymorphic_module(%{"__type__" => type}, metadata),
    do: do_get_polymorphic_module(type, metadata)

  defp do_get_polymorphic_module(%{} = attrs, metadata) do
    # check if one list is contained in another
    # Enum.count(contained -- container) == 0
    # contained -- container == []
    metadata
    |> Enum.filter(&([] != &1.identify_by_fields))
    |> Enum.find(&([] == &1.identify_by_fields -- Map.keys(attrs)))
    |> (&(&1 && Map.fetch!(&1, :module))).()
  end

  defp do_get_polymorphic_module(type, metadata) do
    type = to_string(type)

    metadata
    |> Enum.find(&(type == &1.type))
    |> (&(&1 && Map.fetch!(&1, :module))).()
  end

  def get_polymorphic_type(schema, field, module_or_struct) do
    %{metadata: metadata} = get_options(schema, field)
    do_get_polymorphic_type(module_or_struct, metadata)
  end

  defp do_get_polymorphic_type(%module{}, metadata),
    do: do_get_polymorphic_type(module, metadata)

  defp do_get_polymorphic_type(module, metadata) do
    metadata
    |> Enum.find(&(module == &1.module))
    |> Map.fetch!(:type)
    |> String.to_atom()
  end

  defp get_options(schema, field) do
    try do
      schema.__schema__(:type, field)
    rescue
      _ in UndefinedFunctionError ->
        raise ArgumentError, "#{inspect(schema)} is not an Ecto schema"
    else
      {:parameterized, PolymorphicEmbed, options} -> options
      {_, {:parameterized, PolymorphicEmbed, options}} -> options
      nil -> raise ArgumentError, "#{field} is not an Ecto.Enum field"
    end
  end

  defp convert_map_keys_to_string(%{} = map),
    do: for({key, val} <- map, into: %{}, do: {to_string(key), val})

  defp raise_cannot_infer_type_from_data(data),
    do: raise("could not infer polymorphic embed from data #{inspect(data)}")
end
