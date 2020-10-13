defmodule PolymorphicEmbed do
  @callback get_polymorphic_type(module() | struct()) :: atom()
  @callback get_polymorphic_module(String.t() | atom() | map()) :: atom()

  defmacro __using__(opts) do
    quote do
      @behaviour PolymorphicEmbed

      use PolymorphicEmbed.CustomType, unquote(opts)

      use Ecto.Type

      alias __MODULE__.CustomType

      defdelegate type(), to: CustomType
      defdelegate cast(attrs), to: CustomType
      defdelegate dump(struct), to: CustomType
      defdelegate load(data), to: CustomType
      defdelegate get_polymorphic_type(module_or_struct), to: CustomType.Metadata
      defdelegate get_polymorphic_module(type_or_data), to: CustomType.Metadata
    end
  end
end
