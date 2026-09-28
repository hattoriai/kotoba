defmodule Mix.Tasks.Kotoba.Install do
  @shortdoc "Adds the Kotoba hook, style sheet and storage config to a Phoenix app"

  @moduledoc """
  Sets up Kotoba in a Phoenix application.

      $ mix kotoba.install
      $ mix kotoba.install --dry-run

  The task edits three files:

    * `assets/js/app.js` - adds `import { Kotoba } from "kotoba"` and puts
      `Kotoba` in the `hooks` of the `LiveSocket`. When it cannot find the
      `new LiveSocket(...)` call, or its hooks are not an object or a
      variable, it changes nothing and prints the lines to add.
    * `assets/css/app.css` - adds
      `@import "../../deps/kotoba/priv/static/kotoba.css";`, and the Sumi
      theme import as a comment. The imports follow the deps directory of
      the project (`Mix.Project.deps_path/0`) when it is not `deps/`, as in
      an umbrella child or with `MIX_DEPS_PATH`. For a path dependency
      (`{:kotoba, path: "../kotoba"}`), which Mix does not copy into
      `deps/`, the imports point at the dependency's directory instead.
    * `config/config.exs` - adds `config :kotoba, storage: Kotoba.Storage.Local`,
      with a comment that shows the directory config for
      `config/runtime.exs`.

  Then it prints the `Kotoba.Storage.Local` directory config for the
  `:prod` block of `config/runtime.exs` and for `config/dev.exs` (the adapter needs a `:root`
  before the first upload), the esbuild note (the app's esbuild must resolve `kotoba`
  through `NODE_PATH`: from `deps/`, or, for a path dependency, from the
  directory that holds it) and the router line for
  `Kotoba.Storage.Local.Plug`.

  The task is idempotent: it does not add what a file already has, and when
  there is nothing to add it says so.

  ## Options

    * `--dry-run` - prints the changes as a diff and writes nothing.
  """

  use Mix.Task

  alias Kotoba.Install.Edits

  @js "assets/js/app.js"
  @css "assets/css/app.css"
  @config "config/config.exs"

  @impl Mix.Task
  def run(argv) do
    deps_path = Mix.Project.deps_path()
    install(argv, package_path(Mix.Project.deps_paths(), deps_path), deps_path)
  end

  @doc false
  # The task, with the directory of the Kotoba package and the deps
  # directory of the project given.
  @spec install([String.t()], Path.t(), Path.t()) :: :ok
  def install(argv, package, deps_path \\ "deps") do
    {opts, _args} = OptionParser.parse!(argv, strict: [dry_run: :boolean])
    dry_run? = Keyword.get(opts, :dry_run, false)
    app = Mix.Project.config()[:app] || :my_app

    css_dir = Edits.relative(package, Path.dirname(@css))

    results = [
      edit(@js, &Edits.app_js/1, Edits.app_js_manual(), dry_run?),
      edit(@css, &Edits.app_css(&1, css_dir), Edits.app_css_manual(css_dir), dry_run?),
      edit(@config, &Edits.config(&1, app), config_manual(app), dry_run?)
    ]

    if Enum.all?(results, &(&1 == :unchanged)) do
      Mix.shell().info("Kotoba is already installed. Nothing changed.")
    else
      notes(app, package, deps_path)
    end
  end

  @doc false
  # Where the Kotoba package is, from `Mix.Project.deps_paths/0`: kotoba in
  # the deps directory (`Mix.Project.deps_path/0`, which an umbrella child or
  # MIX_DEPS_PATH moves away from deps/), or the directory of a path
  # dependency (`{:kotoba, path: "../kotoba"}`), which Mix does not copy there.
  @spec package_path(%{optional(atom()) => Path.t()}, Path.t()) :: Path.t()
  def package_path(deps_paths, deps_path \\ "deps") do
    case deps_paths[:kotoba] do
      nil -> Path.expand(Path.join(deps_path, "kotoba"))
      path -> Path.expand(path)
    end
  end

  defp edit(path, fun, manual, dry_run?) do
    case File.read(path) do
      {:ok, source} ->
        apply_edit(path, source, fun.(source), dry_run?)

      {:error, _reason} ->
        Mix.shell().info([:yellow, "* skipping ", :reset, path, " (not found)"])
        Mix.shell().info(indent(manual))
        :manual
    end
  end

  defp apply_edit(path, _source, :unchanged, _dry_run?) do
    Mix.shell().info([:green, "* unchanged ", :reset, path, " (Kotoba is already there)"])
    :unchanged
  end

  defp apply_edit(path, _source, {:manual, text}, _dry_run?) do
    Mix.shell().info([:yellow, "* skipping ", :reset, path, " (add the lines below by hand)"])
    Mix.shell().info(indent(text))
    :manual
  end

  defp apply_edit(path, source, {:changed, new}, true) do
    Mix.shell().info([:cyan, "* would update ", :reset, path])
    Mix.shell().info(Edits.diff(path, source, new))
    :changed
  end

  defp apply_edit(path, source, {:changed, new}, false) do
    File.write!(path, new)
    Mix.shell().info([:green, "* updating ", :reset, path])
    Mix.shell().info(Edits.diff(path, source, new))
    :changed
  end

  defp config_manual(app) do
    "Add the storage config to config/config.exs:\n\n" <> indent(Edits.config_block(app))
  end

  defp notes(app, package, deps_path) do
    config_source =
      case File.read(@config) do
        {:ok, source} -> source
        {:error, _reason} -> ""
      end

    Mix.shell().info("""

    #{esbuild_note(config_source, package, deps_path)}

    Kotoba.Storage.Local needs a directory for the files. Give it one in
    the :prod block of config/runtime.exs, an absolute path outside the
    release (runtime.exs runs in every environment, so outside that block
    it would also replace the development directory):

        if config_env() == :prod do
          config :kotoba, Kotoba.Storage.Local,
            root: System.get_env("KOTOBA_UPLOADS", "/var/lib/#{app}/uploads"),
            url_prefix: "/uploads/kotoba"
        end

    and one for development in config/dev.exs:

        config :kotoba, Kotoba.Storage.Local, root: Path.expand("../tmp/uploads", __DIR__)

    For the Sumi theme, remove the comment marks around the kotoba-sumi.css
    import in assets/css/app.css.

    Serve the uploaded files with Kotoba.Storage.Local.Plug. In your router:

        forward "/uploads/kotoba", Kotoba.Storage.Local.Plug, at: "/"

    or in your endpoint, before the router:

        plug Kotoba.Storage.Local.Plug
    """)
  end

  defp esbuild_note(config_source, package, deps_path) do
    if Path.dirname(package) == Path.expand(deps_path) do
      deps = Edits.relative(deps_path, ".")
      from_config = Edits.relative(deps_path, "config")

      resolves? =
        if deps == "deps",
          do: Edits.node_path?(config_source),
          else: Edits.node_path?(config_source, from_config)

      if resolves? do
        "Your esbuild config sets NODE_PATH to #{deps}/, so `import { Kotoba } from \"kotoba\"` resolves."
      else
        """
        The esbuild profile of your app must resolve `kotoba` from #{deps}/. Give it
        NODE_PATH=#{deps} in config/config.exs:

            env: %{"NODE_PATH" => [Path.expand("#{from_config}", __DIR__), Mix.Project.build_path()]}\
        """
      end
    else
      parent = Edits.relative(Path.dirname(package), "config")

      if Edits.node_path?(config_source, parent) do
        "Your esbuild config has the directory of the Kotoba path dependency in NODE_PATH, so `import { Kotoba } from \"kotoba\"` resolves."
      else
        """
        Kotoba is a path dependency (#{Edits.relative(package, ".")}), so it is not in deps/.
        The esbuild profile of your app finds `kotoba` through NODE_PATH: add the
        directory that holds it to the NODE_PATH in config/config.exs:

            env: %{
              "NODE_PATH" => [
                Path.expand("../deps", __DIR__),
                Path.expand("#{parent}", __DIR__),
                Mix.Project.build_path()
              ]
            }\
        """
      end
    end
  end

  defp indent(text) do
    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> "    " <> line
    end)
  end
end
