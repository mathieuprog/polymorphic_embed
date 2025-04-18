defmodule PolymorphicEmbed.MixProject do
  use Mix.Project

  @version "5.0.3"

  def project do
    [
      app: :polymorphic_embed,
      elixir: "~> 1.13",
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      version: @version,
      package: package(),
      description: "Polymorphic embeds in Ecto",

      # ExDoc
      name: "Polymorphic Embed",
      source_url: "https://github.com/mathieuprog/polymorphic_embed",
      docs: docs(),

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix, :phoenix_html],
        plt_file: {:no_warn, ".plts/polymorphic.plt"}
      ],

      # ExCoveralls
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ecto, "~> 3.12"},
      {:jason, "~> 1.4"},
      {:attrs, "~> 0.6"},
      {:phoenix_html, "~> 4.1", optional: true},
      {:phoenix_html_helpers, "~> 1.0", optional: true},
      {:phoenix_live_view, "~> 0.20 or ~> 1.0", optional: true},
      {:ex_doc, "~> 0.34", only: :dev},
      {:ecto_sql, "~> 3.12", only: :test},
      {:postgrex, "~> 0.18 or ~> 0.19", only: :test},
      {:query_builder, "~> 1.4", only: :test},
      {:phoenix_ecto, "~> 4.6", only: :test},
      {:floki, "~> 0.36", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      test: [
        "ecto.create --quiet",
        "ecto.rollback --all --quiet",
        fn _args ->
          :code.delete(PolymorphicEmbed.CreateTables)
          :code.purge(PolymorphicEmbed.CreateTables)
        end,
        "ecto.migrate --quiet",
        "test"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Mathieu Decaffmeyer"],
      links: %{
        "GitHub" => "https://github.com/mathieuprog/polymorphic_embed",
        "Sponsor" => "https://github.com/sponsors/mathieuprog"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
