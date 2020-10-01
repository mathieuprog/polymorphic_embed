defmodule PolymorphicEmbed do
  defmacro __using__(opts) do
    quote do
      use PolymorphicEmbed.CustomType, unquote(opts)

      use Ecto.Type

      alias __MODULE__.CustomType

      defdelegate type(), to: CustomType
      defdelegate cast(attrs), to: CustomType
      defdelegate load(data), to: CustomType
      defdelegate dump(struct), to: CustomType
      defdelegate get_module_from_type(type), to: CustomType
    end
  end
end
