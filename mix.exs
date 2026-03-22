defmodule Chrona.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/pepicrft/chrona"

  def project do
    [
      app: :chrona,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "Chrona",
      description: "Manage headless Chrome instances via the Chrome DevTools Protocol",
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets],
      mod: {Chrona.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:telemetry, "~> 1.3"},

      # Chrome process management
      {:muontrap, "~> 1.7"},

      # Browser instance pool
      {:nimble_pool, "~> 1.1"},

      # WebSocket client for Chrome DevTools Protocol
      {:websockex, "~> 0.4"},

      # Temporary file management
      {:briefly, "~> 0.5"},

      # Development & Testing
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "Chrona",
      extras: ["README.md"],
      source_ref: @version,
      source_url: @source_url
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end
end
