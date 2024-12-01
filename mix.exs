defmodule Ai.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ilyichv/ai-sdk"

  def project do
    [
      app: :ai_sdk,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Ai.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:finch, "~> 0.19"},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    An Elixir SDK for building AI-powered applications with streaming support and
    easy integration with various AI providers.
    """
  end

  defp package do
    [
      name: "ai",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
