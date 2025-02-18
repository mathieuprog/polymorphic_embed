if Code.ensure_loaded?(Phoenix.HTML) && Code.ensure_loaded?(Phoenix.HTML.Form) do
  defmodule PolymorphicEmbed.HTML.Helpers do
    @doc """
    Returns the polymorphic type of the given field in the given form data.
    """
    def get_polymorphic_type(%Phoenix.HTML.Form{} = form, field) do
      %schema{} = form.source.data

      case form[field] && form[field].value do
        %Ecto.Changeset{data: value} ->
          PolymorphicEmbed.get_polymorphic_type(schema, field, value)

        %_{} = value ->
          PolymorphicEmbed.get_polymorphic_type(schema, field, value)

        %{} = map ->
          case PolymorphicEmbed.get_polymorphic_module(schema, field, map) do
            nil ->
              nil

            module ->
              PolymorphicEmbed.get_polymorphic_type(schema, field, module)
          end

        list when is_list(list) ->
          raise "Cannot infer the polymorphic type as the list of embeds may contain multiple types"

        nil ->
          nil
      end
    end

    def get_polymorphic_type(%Phoenix.HTML.FormField{} = form_field) do
      %{field: field_name, form: parent_form} = form_field
      get_polymorphic_type(parent_form, field_name)
    end

    @doc """
    Returns the source data structure
    """
    def source_data(%Phoenix.HTML.Form{} = form) do
      form.source.data
    end

    @doc """
    Returns the source data structure
    """
    def source_module(%Phoenix.HTML.Form{} = form) do
      form.source.data.__struct__
    end

    def to_form(%{action: parent_action} = source_changeset, form, field, options) do
      id = to_string(form.id <> "_#{field}")
      name = to_string(form.name <> "[#{field}]")

      params = Map.get(source_changeset.params || %{}, to_string(field), %{}) |> List.wrap()

      struct = Ecto.Changeset.apply_changes(source_changeset)

      list_data =
        case Map.get(struct, field) do
          nil ->
            type = Keyword.get(options, :polymorphic_type, get_polymorphic_type(form, field))
            module = PolymorphicEmbed.get_polymorphic_module(struct.__struct__, field, type)
            if module, do: [struct(module)], else: []

          data ->
            List.wrap(data)
        end

      list_data
      |> Enum.with_index()
      |> Enum.map(fn {data, i} ->
        params = Enum.at(params, i) || %{}

        changeset =
          data
          |> Ecto.Changeset.change()
          |> apply_action(parent_action)

        errors = get_errors(changeset)

        changeset = %Ecto.Changeset{
          changeset
          | action: parent_action,
            params: params,
            errors: errors,
            valid?: errors == []
        }

        %schema{} = source_changeset.data

        field_opts = PolymorphicEmbed.get_field_opts(schema, field)
        type_field_name = Map.fetch!(field_opts, :type_field_name)
        # correctly set id and name for embeds_many inputs
        array? = Map.get(field_opts, :array?, false)

        index_string = Integer.to_string(i)

        type = PolymorphicEmbed.get_polymorphic_type(schema, field, changeset.data)

        %Phoenix.HTML.Form{
          source: changeset,
          impl: Phoenix.HTML.FormData.Ecto.Changeset,
          id: if(array?, do: id <> "_" <> index_string, else: id),
          name: if(array?, do: name <> "[" <> index_string <> "]", else: name),
          index: if(array?, do: i),
          errors: errors,
          data: data,
          action: parent_action,
          params: params,
          hidden: [{type_field_name, to_string(type)}],
          options: options
        }
      end)
    end

    # If the parent changeset had no action, we need to remove the action
    # from children changeset so we ignore all errors accordingly.
    defp apply_action(changeset, nil), do: %{changeset | action: nil}
    defp apply_action(changeset, _action), do: changeset

    defp get_errors(%{action: nil}), do: []
    defp get_errors(%{action: :ignore}), do: []
    defp get_errors(%{errors: errors}), do: errors
  end
end
