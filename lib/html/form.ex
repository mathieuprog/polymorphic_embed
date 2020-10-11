if Code.ensure_loaded?(Phoenix.HTML) && Code.ensure_loaded?(Phoenix.HTML.Form) do
  defmodule PolymorphicEmbed.HTML.Form do
    import Phoenix.HTML, only: [html_escape: 1]
    import Phoenix.HTML.Form, only: [hidden_inputs_for: 1]

    def polymorphic_embed_inputs_for(form, field, type, fun)
        when is_atom(field) or is_binary(field) do
      options =
        form.options
        |> Keyword.take([:multipart])

      forms = to_form(form.source, form, field, type, options)

      html_escape(
        Enum.map(forms, fn form ->
          [hidden_inputs_for(form), fun.(form)]
        end)
      )
    end

    def to_form(%{action: parent_action} = source_changeset, form, field, type, options) do
      id = to_string(form.id <> "_#{field}")
      name = to_string(form.name <> "[#{field}]")

      params = Map.get(source_changeset.params || %{}, to_string(field), %{})
      errors = get_errors(source_changeset, field)
      data = get_data(source_changeset, field, type)

      changeset =
        Ecto.Changeset.change(data)
        |> apply_action(parent_action)

      changeset =
        %Ecto.Changeset{
          changeset
          | action: parent_action,
            params: params,
            errors: errors,
            valid?: errors == []
        }
        |> add_changes_for_nested_embeds(params, errors)

      [
        %Phoenix.HTML.Form{
          source: changeset,
          impl: Phoenix.HTML.FormData.Ecto.Changeset,
          id: id,
          name: name,
          errors: errors,
          data: data,
          params: params,
          hidden: [__type__: to_string(type)],
          options: options
        }
      ]
    end

    # If the parent changeset had no action, we need to remove the action
    # from children changeset so we ignore all errors accordingly.
    defp apply_action(changeset, nil), do: %{changeset | action: nil}
    defp apply_action(changeset, _action), do: changeset

    defp get_errors(%{action: nil}, _field), do: []
    defp get_errors(%{action: :ignore}, _field), do: []
    defp get_errors(%{errors: []}, _field), do: []

    defp get_errors(%{errors: errors}, field) do
      Keyword.get(errors, field)
      |> do_get_errors()
    end

    defp do_get_errors(nil), do: []

    defp do_get_errors({_, errors}) do
      errors
      |> Keyword.delete(:type)
      |> Keyword.delete(:validation)
    end

    defp get_data(changeset, field, type) do
      data = Ecto.Changeset.apply_changes(changeset)

      case Map.get(data, field) do
        nil ->
          module = Map.fetch!(changeset.types, field)
          struct(module.get_polymorphic_module(type))

        data ->
          data
      end
    end

    defp add_changes_for_nested_embeds(changeset, params, _errors) when params == %{},
      do: changeset

    defp add_changes_for_nested_embeds(changeset, %{} = params, errors) do
      embeds_fields_as_string =
        changeset.data.__struct__.__schema__(:embeds)
        |> Enum.map(&Atom.to_string(&1))

      embeds_params =
        Enum.filter(params, fn {key, _} -> Enum.member?(embeds_fields_as_string, key) end)
        |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)

      do_add_changes_for_nested_embeds(changeset, embeds_params, errors)
    end

    defp do_add_changes_for_nested_embeds(changeset, [], _errors), do: changeset

    defp do_add_changes_for_nested_embeds(
           changeset,
           [{embed_field, %{} = embed_params} | tail_params],
           errors
         ) do
      embed_errors =
        Enum.find(errors, fn {error_key, _} -> error_key == embed_field end)
        |> case do
          {_, {_, errors}} -> errors
          _ -> []
        end

      embed_data =
        Map.get(changeset.data, embed_field) ||
          get_embed_struct(changeset, embed_field, embed_params)

      embed_changeset =
        %Ecto.Changeset{
          data: embed_data,
          action: changeset.action,
          params: embed_params,
          errors: embed_errors,
          valid?: embed_errors == [],
          changes: %{}
        }
        |> add_changes_for_nested_embeds(embed_params, embed_errors)

      changeset = %{changeset | changes: Map.put(changeset.changes, embed_field, embed_changeset)}

      do_add_changes_for_nested_embeds(changeset, tail_params, embed_errors)
    end

    defp do_add_changes_for_nested_embeds(changeset, [_ | tail_params], errors) do
      do_add_changes_for_nested_embeds(changeset, tail_params, errors)
    end

    defp get_embed_struct(changeset, field, params) do
      changeset
      |> Ecto.Changeset.cast(%{field => params}, [])
      |> Ecto.Changeset.cast_embed(field)
      |> Ecto.Changeset.apply_changes()
      |> Map.fetch!(field)
    end
  end
end
