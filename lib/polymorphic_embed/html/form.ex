if Code.ensure_loaded?(Phoenix.HTML) && Code.ensure_loaded?(Phoenix.HTML.Form) &&
     Code.ensure_loaded?(PhoenixHTMLHelpers.Form) do
  defmodule PolymorphicEmbed.HTML.Form do
    import Phoenix.HTML, only: [html_escape: 1]
    import PhoenixHTMLHelpers.Form, only: [hidden_inputs_for: 1]

    defdelegate get_polymorphic_type(form, field), to: PolymorphicEmbed.HTML.Helpers

    defdelegate get_polymorphic_type(form_field), to: PolymorphicEmbed.HTML.Helpers

    defdelegate source_data(form), to: PolymorphicEmbed.HTML.Helpers

    defdelegate source_module(form), to: PolymorphicEmbed.HTML.Helpers

    defdelegate to_form(source_changeset, form, field, options),
      to: PolymorphicEmbed.HTML.Helpers

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

            <%= case get_polymorphic_type(reminder_form, Reminder, :channel) do %>
              <% :sms -> %>
                <%= label channel_form, :number %>
                <%= text_input channel_form, :number %>

              <% :email -> %>
                <%= label channel_form, :email %>
                <%= text_input channel_form, :email %>
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
                <%= label poly_form, :email %>
                <%= text_input poly_form, :email %>
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
  end
end
