if Code.ensure_compiled(ExMachina) == {:module, ExMachina} do
  defmodule PolymorphicEmbed.ExMachina.Ecto do
    @moduledoc """
    `ExMachina.Ecto` replacement that supports `PolymorphicEmbed`.
    """

    # Copied from https://github.com/thoughtbot/ex_machina/blob/b2f47a36b84fded6c37434bbf9041b33b30387e9/lib/ex_machina/ecto.ex

    defmacro __using__(opts) do
      quote do
        use ExMachina
        use PolymorphicEmbed.ExMachina.EctoStrategy, unquote(opts)

        def params_for(factory_name, attrs \\ %{}) do
          ExMachina.Ecto.params_for(__MODULE__, factory_name, attrs)
        end

        def string_params_for(factory_name, attrs \\ %{}) do
          ExMachina.Ecto.string_params_for(__MODULE__, factory_name, attrs)
        end

        def params_with_assocs(factory_name, attrs \\ %{}) do
          ExMachina.Ecto.params_with_assocs(__MODULE__, factory_name, attrs)
        end

        def string_params_with_assocs(factory_name, attrs \\ %{}) do
          ExMachina.Ecto.string_params_with_assocs(__MODULE__, factory_name, attrs)
        end
      end
    end
  end
end
