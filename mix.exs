defmodule PolymorphicEmbed.MixProject do
  use Mix.Project

  @version "3.0.5"

  def project do
    [
      app: :polymorphic_embed,
      elixir: "~> 1.9",
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
      {:ecto, "~> 3.9"},
      {:jason, "~> 1.4"},
      {:phoenix_html, "~> 2.14 or ~> 3.2", optional: true},
      {:ex_doc, "~> 0.28", only: :dev},
      {:ecto_sql, "~> 3.9", only: :test},
      {:postgrex, "~> 0.16", only: :test},
      {:query_builder, "~> 1.0", only: :test},
      {:phoenix_ecto, "~> 4.4", only: :test},
      {:phoenix_live_view, "~> 0.18", only: :test},
      {:floki, "~> 0.33", only: :test},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.15", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      test: [
        "ecto.create --quiet",
        "ecto.rollback --all",
        "ecto.migrate",
        "test"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["Apache 2.0"],
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
