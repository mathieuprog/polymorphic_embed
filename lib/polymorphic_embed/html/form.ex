if Code.ensure_loaded?(Phoenix.HTML) && Code.ensure_loaded?(Phoenix.HTML.Form) &&
     Code.ensure_loaded?(PhoenixHTMLHelpers.Form) do
  defmodule PolymorphicEmbed.HTML.Form do
    @moduledoc """
    Defines functions for using PolymorphicEmbed with `Phoenix.HTML.Form`.
    """
    import Phoenix.HTML, only: [html_escape: 1]
    import Phoenix.HTML.Form, only: [input_value: 2]
    import PhoenixHTMLHelpers.Form, only: [hidden_inputs_for: 1]

    @doc """
    Returns the polymorphic type of the given field in the given form data.
    """
    def get_polymorphic_type(%Phoenix.HTML.Form{} = form, field) do
      %schema{} = form.source.data
      get_polymorphic_type(form, schema, field)
    end

    def get_polymorphic_type(%Phoenix.HTML.Form{} = form, schema, field) do
      case input_value(form, field) do
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

    @doc """
    Generates a new form builder without an anonymous function.

    Similarly to `Phoenix.HTML.Form.inputs_for/3`, this function exists for
    integration with `Phoenix.LiveView`.

    Unlike `polymorphic_embed_inputs_for/4`, this function does not generate
    hidden inputs.

    ## Example

        <.form
          :let={f}
          for={@changeset}
          id="reminder-form"
          phx-change="validate"
          phx-submit="save"
        >
          <%= for channel_form <- polymorphic_embed_inputs_for f, :channel do %>
            <%= hidden_inputs_for(channel_form) %>

            <%= case get_polymorphic_type(f, Reminder, :channel) do %>
              <% :sms -> %>
                <%= label channel_form, :number %>
                <%= text_input channel_form, :number %>

              <% :email -> %>
                <%= label channel_form, :email_address %>
                <%= text_input channel_form, :address %>
            <% end %>
          <% end %>
        </.form>
    """
    def polymorphic_embed_inputs_for(form, field)
        when is_atom(field) or is_binary(field) do
      options = Keyword.take(form.options, [:multipart])

      to_form(form.source, form, field, options)
    end

    @doc """
    Like `polymorphic_embed_inputs_for/4`, but determines the type from the
    form data.

    ## Example

        <%= inputs_for f, :reminders, fn reminder_form -> %>
          <%= polymorphic_embed_inputs_for reminder_form, :channel, fn channel_form -> %>
            <%= case get_polymorphic_type(reminder_form, Reminder, :channel) do %>
              <% :sms -> %>
                <%= label poly_form, :number %>
                <%= text_input poly_form, :number %>

              <% :email -> %>
                <%= label poly_form, :email_address %>
                <%= text_input poly_form, :address %>
            <% end %>
          <% end %>
        <% end %>

    While `polymorphic_embed_inputs_for/4` renders empty fields if the data is
    `nil`, this function does not. Instead, you can initialize your changeset
    to render an empty fieldset:

        changeset = reminder_changeset(
          %Reminder{},
          %{"channel" => %{"__type__" => "sms"}}
        )
    """
    def polymorphic_embed_inputs_for(form, field, fun)
        when is_atom(field) or is_binary(field) do
      options = Keyword.take(form.options, [:multipart])
      forms = to_form(form.source, form, field, options)

      html_escape(
        Enum.map(forms, fn form ->
          [hidden_inputs_for(form), fun.(form)]
        end)
      )
    end

    def polymorphic_embed_inputs_for(form, field, type \\ nil, fun)
        when is_atom(field) or is_binary(field) do
      options = Keyword.take(form.options, [:multipart])
      forms = to_form(form.source, form, field, [{:polymorphic_type, type} | options])

      html_escape(
        Enum.map(forms, fn form ->
          [hidden_inputs_for(form), fun.(form)]
        end)
      )
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
        type_field_atom = Map.get(field_opts, :type_field_atom, :__type__)
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
          params: params,
          hidden: [{type_field_atom, to_string(type)}],
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
