defmodule PolymorphicEmbed.Polymorphic do
  @moduledoc false

  @callback get_polymorphic_type(module() | struct()) :: atom()

  @doc false
  @spec get_type(module() | struct(), meta_data :: [map()]) :: atom()
  def get_type(%module{}, meta_data),
    do: get_type(module, meta_data)

  def get_type(module, meta_data) when is_atom(module) do
    meta_data
    |> Enum.find(&(module == &1.module))
    |> Map.fetch!(:type)
    |> String.to_atom()
  end
end
