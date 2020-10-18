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

    %{metadata: metadata}
  end

  @impl true
  def cast(attrs, %{metadata: metadata}) do
    # convert keys into string (in case they would be atoms)
    for({key, val} <- attrs, into: %{}, do: {to_string(key), val})
    # get the right module based on the __type__ key or infer from the keys
    |> do_get_polymorphic_module(metadata)
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

  @impl true
  def load(data, _loader, %{metadata: metadata}) do
    struct =
      data
      |> do_get_polymorphic_module(metadata)
      |> cast_to_changeset(data)
      |> Ecto.Changeset.apply_changes()

    {:ok, struct}
  end

  @impl true
  def dump(%_module{} = struct, _dumper, %{metadata: metadata}) do
    Ecto.Type.dump(:map, map_from_struct(struct, :polymorphic_embed, metadata))
  end

  defp map_from_struct(%module{} = struct, :polymorphic_embed, metadata) do
    Map.from_struct(struct)
    |> Map.put(:__type__, do_get_polymorphic_type(module, metadata))
    |> Enum.map(fn {field, value} -> {field, dump_value(field, module, value)} end)
    |> Enum.into(%{})
  end

  defp map_from_struct(%module{} = struct, :embed) do
    Map.from_struct(struct)
    |> Enum.map(fn {field, value} -> {field, dump_value(field, module, value)} end)
    |> Enum.into(%{})
  end

  defp dump_value(field, parent_module, [value | rest_values]) do
    [
      dump_value(field, parent_module, value)
      | dump_value(field, parent_module, rest_values)
    ]
  end

  defp dump_value(field, parent_module, %_module{} = struct) do
    type = parent_module.__schema__(:type, field)

    case type do
      {:parameterized, Ecto.Embedded, _} ->
        {:ok, term} = dump_embed(struct)
        term

      {:embed, _} ->
        {:ok, term} = dump_embed(struct)
        term

      {:parameterized, PolymorphicEmbed, %{metadata: metadata}} ->
        {:ok, term} = dump(struct, nil, %{metadata: metadata})
        term

      _ ->
        struct
    end
  end

  defp dump_value(_, _, value), do: value

  defp dump_embed(struct) do
    Ecto.Type.dump(:map, map_from_struct(struct, :embed))
  end

  def get_polymorphic_module(schema, field, type_or_data) do
    metadata = get_metadata(schema, field)
    do_get_polymorphic_module(type_or_data, metadata)
  end

  defp do_get_polymorphic_module(%{"__type__" => type}, metadata) do
    metadata
    |> Enum.find(&(type == &1.type))
    |> Map.fetch!(:module)
  end

  defp do_get_polymorphic_module(%{} = attrs, metadata) do
    # check if one list is contained in another
    # Enum.count(contained -- container) == 0
    # contained -- container == []
    metadata
    |> Enum.filter(&([] != &1.identify_by_fields))
    |> Enum.find(&([] == &1.identify_by_fields -- Map.keys(attrs)))
    |> case do
      nil ->
        raise "could not infer polymorphic embed from data #{inspect(attrs)}"

      entry ->
        Map.fetch!(entry, :module)
    end
  end

  defp do_get_polymorphic_module(type, metadata) do
    metadata
    |> Enum.find(&(to_string(type) == &1.type))
    |> Map.fetch!(:module)
  end

  def get_polymorphic_type(schema, field, module_or_struct) do
    metadata = get_metadata(schema, field)
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

  defp get_metadata(schema, field) do
    try do
      schema.__schema__(:type, field)
    rescue
      _ in UndefinedFunctionError ->
        raise ArgumentError, "#{inspect(schema)} is not an Ecto schema"
    else
      {:parameterized, PolymorphicEmbed, %{metadata: metadata}} -> metadata
      {_, {:parameterized, PolymorphicEmbed, %{metadata: metadata}}} -> metadata
      nil -> raise ArgumentError, "#{field} is not an Ecto.Enum field"
    end
  end

  defp build_errors(%{errors: errors, changes: changes}) do
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
