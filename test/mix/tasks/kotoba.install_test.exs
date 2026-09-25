defmodule Mix.Tasks.Kotoba.InstallTest do
  # async: false: the task works in the current working directory.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Kotoba.Install

  @fixtures Path.expand("../../fixtures/phoenix", __DIR__)
  @files [
    {"app.js", "assets/js/app.js"},
    {"app.css", "assets/css/app.css"},
    {"config.exs", "config/config.exs"}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "kotoba-install-#{System.unique_integer([:positive])}")

    for {fixture, path} <- @files do
      File.mkdir_p!(Path.dirname(Path.join(root, path)))
      File.cp!(Path.join(@fixtures, fixture), Path.join(root, path))
    end

    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  defp run(root, args \\ []) do
    File.cd!(root, fn -> Install.run(args) end)
    messages([])
  end

  defp messages(acc) do
    receive do
      {:mix_shell, :info, [message]} -> messages([message | acc])
    after
      0 -> acc |> Enum.reverse() |> Enum.join("\n")
    end
  end

  defp read(root, path), do: File.read!(Path.join(root, path))

  defp snapshot(root), do: Map.new(@files, fn {_fixture, path} -> {path, read(root, path)} end)

  test "edits the three files and prints the notes", %{root: root} do
    output = run(root)

    assert read(root, "assets/js/app.js") =~ ~s(import { Kotoba } from "kotoba")
    assert read(root, "assets/js/app.js") =~ "hooks: {...colocatedHooks, Kotoba},"

    assert read(root, "assets/css/app.css") =~
             ~s(@import "../../deps/kotoba/priv/static/kotoba.css";)

    assert read(root, "assets/css/app.css") =~
             "/* @import \"../../deps/kotoba/priv/static/kotoba-sumi.css\"; */"

    assert read(root, "config/config.exs") =~ "config :kotoba, storage: Kotoba.Storage.Local"

    for {_fixture, path} <- @files, do: assert(output =~ "* updating #{path}")
    assert output =~ "+   hooks: {...colocatedHooks, Kotoba},"
    assert output =~ "NODE_PATH"
    assert output =~ ~s|root: System.get_env("KOTOBA_UPLOADS", "/var/lib/kotoba/uploads")|
    assert output =~ "if config_env() == :prod do"

    assert output =~
             ~S|config :kotoba, Kotoba.Storage.Local, root: Path.expand("../tmp/uploads", __DIR__)|

    assert output =~ ~s(forward "/uploads/kotoba", Kotoba.Storage.Local.Plug, at: "/")
  end

  test "a second run changes nothing and says so", %{root: root} do
    run(root)
    before = snapshot(root)

    output = run(root)
    assert snapshot(root) == before
    assert output =~ "Kotoba is already installed. Nothing changed."
    for {_fixture, path} <- @files, do: assert(output =~ "* unchanged #{path}")
    refute output =~ "* updating"
  end

  test "--dry-run prints the diff and writes nothing", %{root: root} do
    before = snapshot(root)
    output = run(root, ["--dry-run"])

    assert snapshot(root) == before
    assert output =~ "* would update assets/js/app.js"
    assert output =~ "--- config/config.exs"
    assert output =~ "+ config :kotoba, storage: Kotoba.Storage.Local"
    assert output =~ ~s(+ @import "../../deps/kotoba/priv/static/kotoba.css";)
  end

  test "prints the lines when it cannot edit app.js, and the NODE_PATH line when it is missing",
       %{root: root} do
    File.write!(Path.join(root, "assets/js/app.js"), "console.log(\"custom\")\n")
    File.write!(Path.join(root, "config/config.exs"), "import Config\n")

    output = run(root)

    assert read(root, "assets/js/app.js") == "console.log(\"custom\")\n"
    assert output =~ "* skipping assets/js/app.js"
    assert output =~ ~s(    import { Kotoba } from "kotoba")

    assert output =~
             ~S|env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}|
  end

  test "says what to add for a file that is not there", %{root: root} do
    File.rm!(Path.join(root, "assets/css/app.css"))
    output = run(root)

    refute File.exists?(Path.join(root, "assets/css/app.css"))
    assert output =~ "* skipping assets/css/app.css (not found)"
    assert output =~ ~s(@import "../../deps/kotoba/priv/static/kotoba.css";)
  end
end
