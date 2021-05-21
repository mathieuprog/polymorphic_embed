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

      params = Map.get(source_changeset.params || %{}, to_string(field), %{}) |> List.wrap()
      list_data = get_data(source_changeset, field, type) |> List.wrap()

      list_data
      |> Enum.with_index()
      |> Enum.map(fn {data, i} ->
        params = Enum.at(params, i) || %{}

        changeset =
          Ecto.Changeset.change(data)
          |> apply_action(parent_action)

        errors = get_errors(changeset)

        changeset =
          %Ecto.Changeset{
            changeset
            | action: parent_action,
              params: params,
              errors: errors,
              valid?: errors == []
          }

        %Phoenix.HTML.Form{
          source: changeset,
          impl: Phoenix.HTML.FormData.Ecto.Changeset,
          id: id,
          index: if(length(list_data) > 1, do: i),
          name: name,
          errors: errors,
          data: data,
          params: params,
          hidden: [__type__: to_string(type)],
          options: options
        }
      end)
    end

    defp get_data(changeset, field, type) do
      struct = Ecto.Changeset.apply_changes(changeset)

      case Map.get(struct, field) do
        nil ->
          struct(PolymorphicEmbed.get_polymorphic_module(struct.__struct__, field, type))

        data ->
          data
      end
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
