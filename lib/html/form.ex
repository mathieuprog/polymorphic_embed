if Code.ensure_loaded?(Phoenix.HTML) do
  defmodule PolymorphicEmbed.HTML.Form do
    import Phoenix.HTML, only: [html_escape: 1]
    import Phoenix.HTML.Form, only: [hidden_inputs_for: 1]

    def polymorphic_embed_inputs_for(form, field, type, fun) when is_atom(field) or is_binary(field) do
      forms = to_form(form.source, form, field, type)

      html_escape(
        Enum.map(forms, fn form ->
          [hidden_inputs_for(form), fun.(form)]
        end)
      )
    end

    def to_form(%{action: parent_action} = source_changeset, form, field, type) do
      id = to_string(form.id <> "_#{field}")
      name = to_string(form.name <> "[#{field}]")

      params = Map.get(source_changeset.params, to_string(field), %{})
      errors = get_errors(source_changeset, field)
      data = get_data(source_changeset, field, type)

      changeset =
        Ecto.Changeset.change(data)
        |> apply_action(parent_action)

      changeset = %Ecto.Changeset{changeset |
        action: parent_action,
        params: params,
        errors: errors,
        valid?: errors != []
      }

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
          options: []
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
          struct(module.get_module_from_type(type))

        data ->
          data
      end
    end
  end
end
