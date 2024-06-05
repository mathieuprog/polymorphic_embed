defmodule PolymorphicEmbed.OptionsValidator do
  require Logger

  @known_options_names [
    :types,
    :on_replace,
    :type_field,
    :type_field_name,
    :on_type_not_found,
    :retain_unlisted_types_on_load,
    :nilify_unlisted_types_on_load,
    # Ecto
    :field,
    :schema,
    :default
  ]
  @valid_on_type_not_found_options [:raise, :changeset_error, :nilify, :ignore]

  def validate!(options) do
    unless is_nil(options[:default]) or options[:default] == [] do
      raise "`:default` expected to be `nil` or `[]`."
    end

    if is_nil(options[:default]) and options[:on_replace] != :update do
      raise "`:on_replace` must be set to `:update` for a single polymorphic embed."
    end

    if is_list(options[:default]) and options[:on_replace] != :delete do
      raise "`:on_replace` must be set to `:delete` for a list of polymorphic embeds."
    end

    unless Keyword.fetch!(options, :on_type_not_found) in @valid_on_type_not_found_options do
      raise(
        "Invalid `:on_type_not_found` option. Valid options: #{@valid_on_type_not_found_options |> Enum.join(", ")}."
      )
    end

    # TODO remove in v5
    if Keyword.has_key?(options, :type_field) do
      Logger.warning(
        "`:type_field` option is deprecated and must be replaced with `:type_field_name`."
      )
    end

    unless is_atom(Keyword.fetch!(options, :type_field_name)) do
      raise "`:type_field_name` must be an atom."
    end

    retain_unlisted_types = Keyword.fetch!(options, :retain_unlisted_types_on_load)
    nilify_unlisted_types = Keyword.fetch!(options, :nilify_unlisted_types_on_load)

    unless is_list(retain_unlisted_types) and Enum.all?(retain_unlisted_types, &is_atom/1) do
      raise "`:retain_unlisted_types_on_load` must be a list of types as atoms."
    end

    unless is_list(nilify_unlisted_types) and Enum.all?(nilify_unlisted_types, &is_atom/1) do
      raise "`:retain_unlisted_types_on_load` must be a list of types as atoms."
    end

    keys = Keyword.keys(options)
    key_count = keys |> Enum.count()
    unique_key_count = Enum.uniq(keys) |> Enum.count()

    if key_count != unique_key_count do
      raise "Duplicate keys found in options for polymorphic embed."
    end

    unknown_options = Keyword.drop(options, @known_options_names)

    if length(unknown_options) > 0 do
      raise "Unknown options: #{unknown_options |> Keyword.keys() |> Enum.join(", ")}"
    end
  end
end
