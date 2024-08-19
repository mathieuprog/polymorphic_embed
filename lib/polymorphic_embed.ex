defmodule PolymorphicEmbed do
  use Ecto.ParameterizedType

  @type t() :: any()

  require Logger
  require PolymorphicEmbed.OptionsValidator

  alias Ecto.Changeset
  alias PolymorphicEmbed.OptionsValidator

  defmacro polymorphic_embeds_one(field_name, opts) do
    opts =
      opts
      |> Keyword.put_new(:array?, false)
      |> Keyword.put_new(:default, nil)
      |> Keyword.update!(:types, &expand_alias(&1, __CALLER__))

    quote do
      field(unquote(field_name), PolymorphicEmbed, unquote(opts))
    end
  end

  defmacro polymorphic_embeds_many(field_name, opts) do
    opts =
      opts
      |> Keyword.put_new(:array?, true)
      |> Keyword.put_new(:default, [])
      |> Keyword.update!(:types, &expand_alias(&1, __CALLER__))

    quote do
      field(unquote(field_name), {:array, PolymorphicEmbed}, unquote(opts))
    end
  end

  # Expand module aliases to avoid creating compile-time dependencies between the
  # parent schema that uses `polymorphic_embeds_one` or `polymorphic_embeds_many`
  # and the embedded schemas.
  defp expand_alias(types, env) when is_list(types) do
    Enum.map(types, fn
      {type_name, type_opts} when is_list(type_opts) ->
        {type_name, Keyword.update!(type_opts, :module, &do_expand_alias(&1, env))}

      {type_name, module} ->
        {type_name, do_expand_alias(module, env)}
    end)
  end

  # If it's not a list or a map, it means it's being defined by a reference of some kind,
  # possibly via module attribute like:
  # @types [twilio: PolymorphicEmbed.Channel.TwilioSMSProvider]
  # # ...
  #   polymorphic_embeds_one(:fallback_provider, types: @types)
  # which means we can't expand aliases
  defp expand_alias(types, env) do
    Logger.warning("""
    Aliases could not be expanded for the given types in #{inspect(env.module)}.

    This likely means the types are defined using a module attribute or another reference
    that cannot be expanded at compile time. As a result, this may lead to unnecessary
    compile-time dependencies, causing longer compilation times and unnecessary
    re-compilation of modules (the parent defining the embedded types).

    Ensure that the types are specified directly within the macro call to avoid these issues,
    or refactor your code to eliminate references that cannot be expanded.
    """)

    types
  end

  defp do_expand_alias({:__aliases__, _, _} = ast, env) do
    Macro.expand(ast, %{env | function: {:__schema__, 2}})
  end

  defp do_expand_alias(ast, _env) do
    ast
  end

  @impl true
  def type(_params), do: :map

  @impl true
  def init(opts) do
    opts = Keyword.put_new(opts, :on_replace, nil)
    # opts = Keyword.put_new(opts, :type_field_name, :__type__)
    # TODO remove in v5
    opts = Keyword.put_new(opts, :type_field_name, Keyword.get(opts, :type_field, :__type__))
    opts = Keyword.put_new(opts, :on_type_not_found, :changeset_error)
    opts = Keyword.put_new(opts, :nilify_unlisted_types_on_load, [])
    opts = Keyword.put_new(opts, :retain_unlisted_types_on_load, [])

    OptionsValidator.validate!(opts)

    if Keyword.get(opts, :on_replace) not in [:update, :delete] do
      raise(
        "`:on_replace` option for polymorphic embed must be set to `:update` (single embed) or `:delete` (list of embeds)"
      )
    end

    types_metadata =
      opts
      |> Keyword.fetch!(:types)
      |> Enum.map(fn
        {type_name, type_opts} when is_list(type_opts) ->
          {type_name, type_opts}

        {type_name, module} ->
          {type_name, module: module}
      end)
      |> Enum.map(fn
        {type_name, type_opts} ->
          %{
            type: type_name,
            module: Keyword.fetch!(type_opts, :module),
            identify_by_fields:
              Keyword.get(type_opts, :identify_by_fields, []) |> Enum.map(&to_string/1)
          }
      end)

    %{
      array?: Keyword.fetch!(opts, :array?),
      default: Keyword.fetch!(opts, :default),
      use_parent_field_for_type: Keyword.get(opts, :use_parent_field_for_type),
      on_replace: Keyword.fetch!(opts, :on_replace),
      on_type_not_found: Keyword.fetch!(opts, :on_type_not_found),
      nilify_unlisted_types_on_load: Keyword.fetch!(opts, :nilify_unlisted_types_on_load),
      retain_unlisted_types_on_load: Keyword.fetch!(opts, :retain_unlisted_types_on_load),
      type_field_name: Keyword.fetch!(opts, :type_field_name),
      types_metadata: types_metadata
    }
  end

  def cast_polymorphic_embed(changeset, field, cast_opts \\ [])

  # credo:disable-for-next-line
  def cast_polymorphic_embed(%Ecto.Changeset{} = changeset, field, cast_opts) do
    field_opts = get_field_opts(changeset.data.__struct__, field)

    raise_if_invalid_options(field, field_opts)

    %{array?: array?, types_metadata: types_metadata} = field_opts

    required = Keyword.get(cast_opts, :required, false)
    with = Keyword.get(cast_opts, :with, nil)

    changeset_fun = &changeset_fun(&1, &2, with, types_metadata)

    # used for sort_param and drop_param support for many embeds
    sort = param_value_for_cast_opt(:sort_param, cast_opts, changeset.params)
    drop = param_value_for_cast_opt(:drop_param, cast_opts, changeset.params)

    case Map.fetch(changeset.params || %{}, to_string(field)) do
      # consider sort and drop params even if the assoc param was not given, as in Ecto
      :error when (array? and is_list(sort)) or is_list(drop) ->
        create_sort_default = fn -> sort_create(Enum.into(cast_opts, %{}), field_opts) end
        params_for_field = apply_sort_drop(%{}, sort, drop, create_sort_default)

        cast_polymorphic_embeds_many(
          changeset,
          field,
          changeset_fun,
          params_for_field,
          field_opts
        )

      :error when required ->
        if data_for_field = Map.fetch!(changeset.data, field) do
          data_for_field = autogenerate_id(data_for_field, changeset.action)
          Ecto.Changeset.put_change(changeset, field, data_for_field)
        else
          Ecto.Changeset.add_error(changeset, field, "can't be blank", validation: :required)
        end

      :error when not required ->
        if data_for_field = Map.fetch!(changeset.data, field) do
          data_for_field = autogenerate_id(data_for_field, changeset.action)
          Ecto.Changeset.put_change(changeset, field, data_for_field)
        else
          changeset
        end

      {:ok, nil} when required ->
        Ecto.Changeset.add_error(changeset, field, "can't be blank", validation: :required)

      {:ok, nil} when not required ->
        Ecto.Changeset.put_change(changeset, field, nil)

      {:ok, map} when map == %{} and not array? ->
        changeset

      {:ok, params_for_field} when array? ->
        create_sort_default = fn -> sort_create(Enum.into(cast_opts, %{}), field_opts) end
        params_for_field = apply_sort_drop(params_for_field, sort, drop, create_sort_default)

        cast_polymorphic_embeds_many(
          changeset,
          field,
          changeset_fun,
          params_for_field,
          field_opts
        )

      {:ok, params_for_field} when is_map(params_for_field) and not array? ->
        cast_polymorphic_embeds_one(
          changeset,
          field,
          changeset_fun,
          params_for_field,
          field_opts
        )
    end
  end

  def cast_polymorphic_embed(_, _, _) do
    raise "cast_polymorphic_embed/3 only accepts a changeset as first argument"
  end

  defp sort_create(%{sort_param: _} = cast_opts, field_opts) do
    default_type = Map.get(cast_opts, :default_type_on_sort_create)
    type_field_name = Map.fetch!(field_opts, :type_field_name)
    types_metadata = Map.fetch!(field_opts, :types_metadata)

    case default_type do
      nil ->
        # If type is not provided, use the first type from types_metadata
        [first_type_metadata | _] = types_metadata
        first_type = first_type_metadata.type
        %{type_field_name => first_type}

      _ ->
        default_type =
          case default_type do
            fun when is_function(fun, 0) -> fun.()
            _ -> default_type
          end

        # If type is provided, ensure it exists in types_metadata
        unless Enum.find(types_metadata, &(&1.type === default_type)) do
          raise "incorrect type atom #{inspect(default_type)}"
        end

        %{type_field_name => default_type}
    end
  end

  defp sort_create(_cast_opts, _field_opts), do: nil

  defp apply_sort_drop(value, sort, drop, create_sort_default) when is_map(value) do
    drop = if is_list(drop), do: drop, else: []

    {sorted, pending} =
      if is_list(sort) do
        Enum.map_reduce(sort -- drop, value, &Map.pop(&2, &1, create_sort_default.()))
      else
        {[], value}
      end

    sorted ++
      (pending
       |> Map.drop(drop)
       |> Enum.map(&key_as_int/1)
       |> Enum.sort()
       |> Enum.map(&elem(&1, 1)))
  end

  defp apply_sort_drop(value, _sort, _drop, _default) do
    value
  end

  defp param_value_for_cast_opt(opt, opts, params) do
    if key = opts[opt] do
      Map.get(params, Atom.to_string(key), nil)
    end
  end

  defp key_as_int({key, val}) when is_binary(key) do
    case Integer.parse(key) do
      {key, ""} -> {key, val}
      _ -> {key, val}
    end
  end

  # from Ecto
  # We check for the byte size to avoid creating unnecessary large integers
  # which would never map to a database key (u64 is 20 digits only).
  defp key_as_int({key, val}) when is_binary(key) and byte_size(key) < 32 do
    case Integer.parse(key) do
      {key, ""} -> {key, val}
      _ -> {key, val}
    end
  end

  defp key_as_int(key_val), do: key_val

  defp changeset_fun(struct, params, with, types_metadata) when is_list(with) do
    type = do_get_polymorphic_type(struct, types_metadata)

    case Keyword.get(with, type) do
      {module, function_name, args} ->
        apply(module, function_name, [struct, params | args])

      nil ->
        struct.__struct__.changeset(struct, params)

      fun ->
        apply(fun, [struct, params])
    end
  end

  defp changeset_fun(struct, params, nil, _) do
    struct.__struct__.changeset(struct, params)
  end

  defp cast_polymorphic_embeds_one(changeset, field, changeset_fun, params, field_opts) do
    %{on_type_not_found: on_type_not_found} = field_opts

    data_for_field = Map.fetch!(changeset.data, field)

    # We support partial update of the embed. If the type cannot be inferred from the parameters, or if the found type
    # hasn't changed, pass the data to the changeset.

    case action_and_struct(changeset, params, field_opts, data_for_field) do
      :type_not_found when on_type_not_found == :raise ->
        raise_cannot_infer_type_from_data(params)

      :type_not_found when on_type_not_found == :changeset_error ->
        Ecto.Changeset.add_error(changeset, field, "is invalid")

      :type_not_found when on_type_not_found == :nilify ->
        Ecto.Changeset.put_change(changeset, field, nil)

      {action, struct} ->
        embed_changeset = changeset_fun.(struct, params)
        embed_changeset = %{embed_changeset | action: action}

        case embed_changeset do
          %{valid?: true} = embed_changeset ->
            embed_schema = Ecto.Changeset.apply_changes(embed_changeset)
            embed_schema = autogenerate_id(embed_schema, embed_changeset.action)
            Ecto.Changeset.put_change(changeset, field, embed_schema)

          %{valid?: false} = embed_changeset ->
            changeset
            |> Ecto.Changeset.put_change(field, embed_changeset)
            |> Map.put(:valid?, false)
        end
    end
  end

  defp action_and_struct(changeset, params, field_opts, data_for_field) do
    %{
      types_metadata: types_metadata,
      type_field_name: type_field_name,
      use_parent_field_for_type: parent_field_for_type
    } = field_opts

    if parent_field_for_type != nil do
      type_from_map = Attrs.get(params, type_field_name)
      type_from_parent_field = Ecto.Changeset.fetch_field!(changeset, parent_field_for_type)

      cond do
        is_nil(type_from_parent_field) ->
          :type_not_found

        is_nil(type_from_map) ->
          module = get_polymorphic_module_for_type(type_from_parent_field, types_metadata)

          if is_nil(data_for_field) or data_for_field.__struct__ != module do
            {:insert, struct(module)}
          else
            {:update, data_for_field}
          end

        to_string(type_from_parent_field) != to_string(type_from_map) ->
          raise "type specified in the parent field \"#{type_from_parent_field}\" does not match the type in the embedded map \"#{type_from_map}\""
      end
    else
      case get_polymorphic_module_from_map(params, type_field_name, types_metadata) do
        nil ->
          if data_for_field do
            {:update, data_for_field}
          else
            :type_not_found
          end

        module when is_nil(data_for_field) ->
          {:insert, struct(module)}

        module ->
          if data_for_field.__struct__ != module do
            {:insert, struct(module)}
          else
            {:update, data_for_field}
          end
      end
    end
  end

  defp cast_polymorphic_embeds_many(changeset, field, changeset_fun, list_params, field_opts) do
    %{
      types_metadata: types_metadata,
      on_type_not_found: on_type_not_found,
      type_field_name: type_field_name
    } = field_opts

    list_data_for_field = Map.fetch!(changeset.data, field) || []

    embeds =
      Enum.map(list_params, fn params ->
        case get_polymorphic_module_from_map(params, type_field_name, types_metadata) do
          nil when on_type_not_found == :raise ->
            raise_cannot_infer_type_from_data(params)

          nil when on_type_not_found == :changeset_error ->
            :error

          nil when on_type_not_found == :ignore ->
            :ignore

          module ->
            data_for_field =
              Enum.find(list_data_for_field, fn
                %{id: id} = datum when not is_nil(id) ->
                  id == params[:id] and datum.__struct__ == module

                _ ->
                  nil
              end)

            embed_changeset =
              if data_for_field do
                %{changeset_fun.(data_for_field, params) | action: :update}
              else
                %{changeset_fun.(struct(module), params) | action: :insert}
              end

            maybe_apply_changes(embed_changeset)
        end
      end)

    if Enum.any?(embeds, &(&1 == :error)) do
      Ecto.Changeset.add_error(changeset, field, "is invalid")
    else
      embeds = Enum.filter(embeds, &(&1 != :ignore))

      any_invalid? =
        Enum.any?(embeds, fn
          %{valid?: false} -> true
          _ -> false
        end)

      changeset = Ecto.Changeset.put_change(changeset, field, embeds)

      if any_invalid? do
        Map.put(changeset, :valid?, false)
      else
        changeset
      end
    end
  end

  defp maybe_apply_changes(%{valid?: true} = embed_changeset) do
    embed_changeset
    |> Ecto.Changeset.apply_changes()
    |> autogenerate_id(embed_changeset.action)
  end

  defp maybe_apply_changes(%Changeset{valid?: false} = changeset), do: changeset

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

  def load(data, loader, params) when is_map(data), do: do_load(data, loader, params)

  def load(data, loader, params) when is_binary(data),
    do: do_load(Jason.decode!(data), loader, params)

  def do_load(data, _loader, field_opts) do
    %{
      types_metadata: types_metadata,
      type_field_name: type_field_name
    } = field_opts

    case get_polymorphic_module_from_map(data, type_field_name, types_metadata) do
      nil ->
        retain_type_list =
          Map.fetch!(field_opts, :retain_unlisted_types_on_load) |> Enum.map(&to_string(&1))

        nilify_type_list =
          Map.fetch!(field_opts, :nilify_unlisted_types_on_load) |> Enum.map(&to_string(&1))

        type = Map.get(data, type_field_name |> to_string)

        cond do
          type in retain_type_list ->
            {:ok, data}

          type in nilify_type_list ->
            {:ok, nil}

          true ->
            raise_cannot_infer_type_from_data(data)
        end

      module when is_atom(module) ->
        {:ok, Ecto.embedded_load(module, data, :json)}
    end
  end

  @impl true
  def dump(%Ecto.Changeset{valid?: false}, _dumper, _params) do
    raise "cannot dump invalid changeset"
  end

  def dump(%Ecto.Changeset{valid?: true} = changeset, dumper, params) do
    dump(Ecto.Changeset.apply_changes(changeset), dumper, params)
  end

  def dump(%module{} = struct, dumper, %{
        types_metadata: types_metadata,
        type_field_name: type_field_name
      }) do
    case module.__schema__(:autogenerate_id) do
      {key, _source, :binary_id} ->
        unless Map.get(struct, key) do
          raise "polymorphic_embed is not able to add an autogenerated key without casting through cast_polymorphic_embed/3"
        end

      _ ->
        nil
    end

    map =
      struct
      |> map_from_struct()
      # use the atom instead of string form for mongodb
      |> Map.put(type_field_name, do_get_polymorphic_type(module, types_metadata))

    dumper.(:map, map)
  end

  def dump(nil, dumper, _params), do: dumper.(:map, nil)

  defp map_from_struct(struct) do
    Ecto.embedded_dump(struct, :json)
  end

  def get_polymorphic_module(schema, field, type_or_data) do
    %{types_metadata: types_metadata, type_field_name: type_field_name} =
      get_field_opts(schema, field)

    case type_or_data do
      map when is_map(map) ->
        get_polymorphic_module_from_map(map, type_field_name, types_metadata)

      type when is_atom(type) or is_binary(type) ->
        get_polymorphic_module_for_type(type, types_metadata)
    end
  end

  defp get_polymorphic_module_from_map(%{} = attrs, type_field_name, types_metadata) do
    if type = Attrs.get(attrs, type_field_name) do
      get_polymorphic_module_for_type(type, types_metadata)
    else
      # check if one list is contained in another
      # Enum.count(contained -- container) == 0
      # contained -- container == []

      types_metadata =
        types_metadata
        |> Enum.filter(&([] != &1.identify_by_fields))

      if types_metadata != [] do
        keys = Map.keys(attrs) |> Enum.map(&to_string/1)

        types_metadata
        |> Enum.find(&([] == &1.identify_by_fields -- keys))
        |> (&(&1 && Map.fetch!(&1, :module))).()
      else
        nil
      end
    end
  end

  defp get_polymorphic_module_for_type(type, types_metadata) do
    get_metadata_for_type(type, types_metadata)
    |> (&(&1 && Map.fetch!(&1, :module))).()
  end

  def get_polymorphic_type(schema, field, module_or_struct) do
    %{types_metadata: types_metadata} = get_field_opts(schema, field)
    do_get_polymorphic_type(module_or_struct, types_metadata)
  end

  defp do_get_polymorphic_type(%module{}, types_metadata),
    do: do_get_polymorphic_type(module, types_metadata)

  defp do_get_polymorphic_type(module, types_metadata) do
    get_metadata_for_module(module, types_metadata)
    |> Map.fetch!(:type)
  end

  @doc """
  Returns the possible types for a given schema and field

  you can call `types/2` like this:
      PolymorphicEmbed.types(MySchema, :contexts)
      #=> [:location, :age, :device]
  """
  def types(schema, field) do
    %{types_metadata: types_metadata} = get_field_opts(schema, field)
    Enum.map(types_metadata, & &1.type)
  end

  defp get_metadata_for_module(module, types_metadata) do
    Enum.find(types_metadata, &(module == &1.module))
  end

  defp get_metadata_for_type(type, types_metadata) do
    type = to_string(type)
    Enum.find(types_metadata, &(type == to_string(&1.type)))
  end

  @doc false
  def get_field_opts(schema, field) do
    try do
      schema.__schema__(:type, field)
    rescue
      _ in UndefinedFunctionError ->
        reraise ArgumentError, "#{inspect(schema)} is not an Ecto schema", __STACKTRACE__
    else
      {:parameterized, {PolymorphicEmbed, options}} -> Map.put(options, :array?, false)
      {:array, {:parameterized, {PolymorphicEmbed, options}}} -> Map.put(options, :array?, true)
      {_, {:parameterized, {PolymorphicEmbed, options}}} -> Map.put(options, :array?, false)
      nil -> raise ArgumentError, "#{field} is not a polymorphic embed"
    end
  end

  defp raise_if_invalid_options(field, %{array?: array?, default: default, on_replace: on_replace}) do
    if array? and default != [] do
      raise "`:default` option for list of polymorphic embeds is required and must be set to `[]`"
    end

    if array? and on_replace != :delete do
      raise "`:on_replace` option for field #{inspect(field)} must be set to `:delete`"
    end

    if not array? and on_replace != :update do
      raise "`:on_replace` option for field #{inspect(field)} must be set to `:update`"
    end
  end

  defp raise_cannot_infer_type_from_data(data),
    do: raise("could not infer polymorphic embed from data #{inspect(data)}")

  def traverse_errors(%Ecto.Changeset{changes: changes, types: types} = changeset, msg_func)
      when is_function(msg_func, 1) or is_function(msg_func, 3) do
    changeset
    |> Ecto.Changeset.traverse_errors(msg_func)
    |> merge_polymorphic_keys(changes, types, msg_func)
  end

  # We need to match the case where an invalid changeset has a PolymorphicEmbed field which is valid,
  # then that PolymorphicEmbed field is already converted to a struct and no longer a changeset.
  # Since the said field is converted to a struct there's errors to check for.
  def traverse_errors(%_{}, msg_func)
      when is_function(msg_func, 1) or is_function(msg_func, 3) do
    %{}
  end

  defp merge_polymorphic_keys(map, changes, types, msg_func) do
    Enum.reduce(types, map, &polymorphic_key_reducer(&1, &2, changes, msg_func))
  end

  defp polymorphic_key_reducer(
         {field, {rel, %{cardinality: :one}}},
         acc,
         changes,
         msg_func
       )
       when rel in [:assoc, :embed] do
    if changeset = Map.get(changes, field) do
      case traverse_errors(changeset, msg_func) do
        errors when errors == %{} -> acc
        errors -> Map.put(acc, field, errors)
      end
    else
      acc
    end
  end

  defp polymorphic_key_reducer(
         {field, {:parameterized, {PolymorphicEmbed, _opts}}},
         acc,
         changes,
         msg_func
       ) do
    if changeset = Map.get(changes, field) do
      case traverse_errors(changeset, msg_func) do
        errors when errors == %{} -> acc
        errors -> Map.put(acc, field, errors)
      end
    else
      acc
    end
  end

  defp polymorphic_key_reducer(
         {field, {rel, %{cardinality: :many}}},
         acc,
         changes,
         msg_func
       )
       when rel in [:assoc, :embed] do
    if changesets = Map.get(changes, field) do
      {errors, all_empty?} =
        Enum.map_reduce(changesets, true, fn changeset, all_empty? ->
          errors = traverse_errors(changeset, msg_func)
          {errors, all_empty? and errors == %{}}
        end)

      case all_empty? do
        true -> acc
        false -> Map.put(acc, field, errors)
      end
    else
      acc
    end
  end

  defp polymorphic_key_reducer(
         {field, {:array, {:parameterized, {PolymorphicEmbed, _opts}}}},
         acc,
         changes,
         msg_func
       ) do
    if changesets = Map.get(changes, field) do
      {errors, all_empty?} =
        Enum.map_reduce(changesets, true, fn changeset, all_empty? ->
          errors = traverse_errors(changeset, msg_func)
          {errors, all_empty? and errors == %{}}
        end)

      case all_empty? do
        true -> acc
        false -> Map.put(acc, field, errors)
      end
    else
      acc
    end
  end

  defp polymorphic_key_reducer({_, _}, acc, _, _), do: acc

  defp autogenerate_id([], _action), do: []

  defp autogenerate_id([schema | rest], action) do
    [autogenerate_id(schema, action) | autogenerate_id(rest, action)]
  end

  defp autogenerate_id(schema, :update) do
    # in case there is no primary key, Ecto.primary_key/1 returns an empty keyword list []
    for {_, nil} <- Ecto.primary_key(schema) do
      raise("no primary key found in #{inspect(schema)}")
    end

    schema
  end

  defp autogenerate_id(schema, action) when action in [nil, :insert] do
    case schema.__struct__.__schema__(:autogenerate_id) do
      {key, _source, :binary_id} ->
        if Map.get(schema, key) == nil do
          Map.put(schema, key, Ecto.UUID.generate())
        else
          schema
        end

      {_key, :id} ->
        raise("embedded schemas cannot autogenerate `:id` primary keys")

      nil ->
        schema
    end
  end
end
