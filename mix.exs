defmodule Kotoba.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/hattoriai/kotoba"

  def project do
    [
      app: :kotoba,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [&String.starts_with?(&1, "test/fixtures/")],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # For the code reloader of the development server (dev.exs).
      listeners: [Phoenix.CodeReloader],
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit, :esbuild],
        plt_file: {:no_warn, "priv/plts/project.plt"}
      ],
      package: package(),
      docs: docs(),
      description: description(),
      name: "Kotoba",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.5", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ecto, "~> 3.13"},
      {:esbuild, "~> 0.10", only: :dev, runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end

  defp description do
    "Rich text for Phoenix: a prebuilt Lexical editor, an Ecto content type, rendering and sanitization."
  end

  defp package do
    [
      name: "kotoba",
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      # The four bundle files by name: other build output in priv/static
      # never goes into the package.
      files: ~w(
        lib
        priv/static/kotoba.esm.js
        priv/static/kotoba.cjs.js
        priv/static/kotoba.css
        priv/static/kotoba-sumi.css
        package.json
        mix.exs
        .formatter.exs
        README.md
        CHANGELOG.md
        LICENSE
        NOTICE
      )
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  # The browser tests need their npm packages; `npm ci` runs once.
  defp e2e_deps(_args) do
    unless File.dir?("e2e/node_modules") do
      Mix.Task.run("cmd", ~w(--cd e2e npm ci))
    end
  end

  defp aliases do
    [
      "assets.build": ["kotoba.build"],
      dev: "run --no-halt dev.exs",
      "test.e2e": [&e2e_deps/1, "cmd --cd e2e npm test"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "test"
      ]
    ]
  end
end
