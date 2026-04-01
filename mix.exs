defmodule ExBrand.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_brand,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_options: [warnings_as_errors: true],
      consolidate_protocols: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_local_path: "priv/plts",
      ignore_warnings: ".dialyzer_ignore.exs",
      flags: [:error_handling, :missing_return, :underspecs]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/getting-started.md",
        "docs/api-guide.md"
      ],
      source_ref: "main"
    ]
  end
end
