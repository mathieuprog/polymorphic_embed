if Code.ensure_loaded?(Phoenix.HTML) && Code.ensure_loaded?(Phoenix.HTML.Form) &&
     Code.ensure_loaded?(Phoenix.Component) do
  defmodule PolymorphicEmbed.HTML.Component do
    use Phoenix.Component

    import PolymorphicEmbed.HTML.Helpers

    @doc """
    Renders nested form inputs for polymorphic embeds.

    See `Phoenix.Component.inputs_for/1`.
    """
    @doc type: :component
    attr(:field, Phoenix.HTML.FormField,
      required: true,
      doc: "A %Phoenix.HTML.Form{}/field name tuple, for example: {@form[:email]}."
    )

    attr(:id, :string,
      doc: """
      The id to be used in the form, defaults to the concatenation of the given
      field to the parent form id.
      """
    )

    attr(:as, :atom,
      doc: """
      The name to be used in the form, defaults to the concatenation of the given
      field to the parent form name.
      """
    )

    attr(:default, :any, doc: "The value to use if none is available.")

    attr(:prepend, :list,
      doc: """
      The values to prepend when rendering. This only applies if the field value
      is a list and no parameters were sent through the form.
      """
    )

    attr(:append, :list,
      doc: """
      The values to append when rendering. This only applies if the field value
      is a list and no parameters were sent through the form.
      """
    )

    attr(:skip_hidden, :boolean,
      default: false,
      doc: """
      Skip the automatic rendering of hidden fields to allow for more tight control
      over the generated markup.
      """
    )

    slot(:inner_block, required: true, doc: "The content rendered for each nested form.")

    @persistent_id "_persistent_id"
    def polymorphic_embed_inputs_for(assigns) do
      %Phoenix.HTML.FormField{field: field_name, form: parent_form} = assigns.field
      options = assigns |> Map.take([:id, :as, :default, :append, :prepend]) |> Keyword.new()

      options =
        parent_form.options
        |> Keyword.take([:multipart])
        |> Keyword.merge(options)

      forms =
        to_form(
          parent_form.source,
          parent_form,
          field_name,
          options
        )

      seen_ids = for f <- forms, vid = f.params[@persistent_id], into: %{}, do: {vid, true}

      {forms, _} =
        Enum.map_reduce(forms, seen_ids, fn %Phoenix.HTML.Form{params: params} = form, seen_ids ->
          id =
            case params do
              %{@persistent_id => id} -> id
              %{} -> next_id(map_size(seen_ids), seen_ids)
            end

          form_id = "#{parent_form.id}_#{field_name}_#{id}"
          new_params = Map.put(params, @persistent_id, id)
          new_hidden = [{@persistent_id, id} | form.hidden]

          new_form = %Phoenix.HTML.Form{
            form
            | id: form_id,
              params: new_params,
              hidden: new_hidden
          }

          {new_form, Map.put(seen_ids, id, true)}
        end)

      assigns = assign(assigns, :forms, forms)

      ~H"""
      <%= for finner <- @forms do %>
        <%= unless @skip_hidden do %>
          <%= for {name, value_or_values} <- finner.hidden,
                  id = Phoenix.HTML.Form.input_id(finner, name),
                  name = name_for_value_or_values(finner, name, value_or_values),
                  value <- List.wrap(value_or_values) do %>
            <input type="hidden" id={id} name={name} value={value} />
          <% end %>
        <% end %>
        <%= render_slot(@inner_block, finner) %>
      <% end %>
      """
    end

    def persistent_id_key() do
      @persistent_id
    end

    defp next_id(idx, %{} = seen_ids) do
      id_str = to_string(idx)

      if Map.has_key?(seen_ids, id_str) do
        next_id(idx + 1, seen_ids)
      else
        id_str
      end
    end

    defp name_for_value_or_values(form, field, values) when is_list(values) do
      Phoenix.HTML.Form.input_name(form, field) <> "[]"
    end

    defp name_for_value_or_values(form, field, _value) do
      Phoenix.HTML.Form.input_name(form, field)
    end
  end
end
