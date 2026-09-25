defmodule Mix.Tasks.Kotoba.Gen.NodeTest do
  # async: false: the task writes relative to the working directory.
  use ExUnit.Case, async: false

  alias Kotoba.{Document, Renderer}
  alias Mix.Tasks.Kotoba.Gen.Node, as: GenNode

  @app "gen_probe"

  setup do
    root = Path.join(System.tmp_dir!(), "kotoba-gen-node-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "lib"))
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  defp run(root, args), do: File.cd!(root, fn -> GenNode.run(args ++ ["--app", @app]) end)

  defp read(root, path), do: File.read!(Path.join(root, path))

  defp messages do
    receive_messages([])
  end

  defp receive_messages(acc) do
    receive do
      {:mix_shell, :info, [message]} -> receive_messages([message | acc])
    after
      0 -> acc |> Enum.reverse() |> Enum.join("\n")
    end
  end

  # Compiles the generated module, and removes it after the test.
  defp compile!(source, file) do
    [{module, _binary}] = Code.compile_string(source, file)

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    module
  end

  # Runs the generated ExUnit test in this process: each `test` block
  # becomes a function of a module with the same attributes and helpers.
  defp run_generated_test!(source) do
    {:defmodule, meta, [alias, [do: {:__block__, block_meta, body}]]} =
      Code.string_to_quoted!(source)

    {body, names} =
      Enum.map_reduce(body, [], fn
        {:use, _meta, [{:__aliases__, _, [:ExUnit, :Case]} | _opts]}, names ->
          {quote(do: import(ExUnit.Assertions)), names}

        {:test, _meta, [name, [do: test_body]]}, names ->
          fun = String.to_atom("test " <> name)
          {quote(do: def(unquote(fun)(), do: unquote(test_body))), [fun | names]}

        other, names ->
          {other, names}
      end)

    [{module, _binary}] =
      Code.compile_quoted({:defmodule, meta, [alias, [do: {:__block__, block_meta, body}]]})

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    for name <- Enum.reverse(names), do: apply(module, name, [])
    length(names)
  end

  defp js_check!(root, path) do
    case System.find_executable("node") do
      nil ->
        IO.puts("node is not on the path, so the generated JavaScript is not checked")
        :skipped

      node ->
        # A .mjs copy: node reads it as an ES module whatever the package type.
        module = Path.join(root, "node.mjs")
        File.cp!(Path.join(root, path), module)
        assert {_output, 0} = System.cmd(node, ["--check", module], stderr_to_stdout: true)

        script = Path.join(root, "probe.mjs")

        File.write!(script, """
        class DecoratorNode {
          constructor(key) { this.__key = key }
          getLatest() { return this }
        }
        const factory = (await import("./node.mjs")).default
        const Klass = factory({ DecoratorNode })
        const node = Klass.importJSON({ type: Klass.getType(), version: 1, label: "Hi" })
        const copy = Klass.clone(node)
        console.log(JSON.stringify({
          type: Klass.getType(),
          json: copy.exportJSON(),
          inline: node.isInline(),
          text: node.getTextContent(),
          extends: node instanceof DecoratorNode,
        }))
        """)

        {output, 0} = System.cmd(node, [script], stderr_to_stdout: true)
        JSON.decode!(String.trim(output))
    end
  end

  test "writes the Elixir module, the JavaScript module and the test", %{root: root} do
    run(root, ["Callout"])

    assert File.exists?(Path.join(root, "lib/gen_probe/kotoba/nodes/callout.ex"))
    assert File.exists?(Path.join(root, "assets/js/kotoba/nodes/callout.js"))
    assert File.exists?(Path.join(root, "test/gen_probe/kotoba/nodes/callout_test.exs"))

    output = messages()
    assert output =~ "* creating lib/gen_probe/kotoba/nodes/callout.ex"
    assert output =~ "config :kotoba, nodes: [GenProbe.Kotoba.Nodes.Callout]"

    assert output =~
             ~s|nodes={[{GenProbe.Kotoba.Nodes.Callout, ~p"/assets/kotoba/nodes/callout.js"}]}|

    assert output =~ "esbuild"
  end

  test "the decorator module compiles, parses and renders", %{root: root} do
    run(root, ["Callout"])
    source = read(root, "lib/gen_probe/kotoba/nodes/callout.ex")

    assert Code.format_string!(source, locals_without_parens: [field: 2, field: 3])
           |> IO.iodata_to_binary()
           |> Kernel.<>("\n") == source

    module = compile!(source, "callout.ex")
    assert module == GenProbe.Kotoba.Nodes.Callout
    assert module.type() == "gen-probe-callout"
    assert module.kind() == :decorator
    assert Enum.map(module.fields(), & &1.key) == ["label", "version"]

    doc = %{
      "kotoba" => 1,
      "lexical" => "0.51",
      "root" => %{
        "type" => "root",
        "children" => [%{"type" => module.type(), "version" => 1, "label" => "<i>Note</i>"}]
      }
    }

    assert {:ok, parsed} = Document.parse(doc, nodes: [module])

    assert parsed |> Renderer.to_html() |> Phoenix.HTML.safe_to_string() ==
             ~s(<div class="gen-probe-callout">&lt;i&gt;Note&lt;/i&gt;</div>)

    assert Renderer.to_text(parsed) == "<i>Note</i>"
    assert Renderer.to_markdown(parsed) == "\\<i>Note\\</i>"

    assert run_generated_test!(read(root, "test/gen_probe/kotoba/nodes/callout_test.exs")) ==
             2
  end

  test "the decorator JavaScript parses and mirrors the Elixir fields", %{root: root} do
    run(root, ["Callout"])

    case js_check!(root, "assets/js/kotoba/nodes/callout.js") do
      :skipped ->
        :ok

      result ->
        assert result == %{
                 "type" => "gen-probe-callout",
                 "json" => %{
                   "type" => "gen-probe-callout",
                   "version" => 1,
                   "label" => "Hi"
                 },
                 "inline" => false,
                 "text" => "Hi",
                 "extends" => true
               }
    end
  end

  test "an inline node goes in a paragraph", %{root: root} do
    run(root, ["StatusChip", "--kind", "inline"])

    source = read(root, "lib/gen_probe/kotoba/nodes/status_chip.ex")
    module = compile!(source, "status_chip.ex")
    assert module.type() == "gen-probe-status-chip"
    assert module.kind() == :inline
    assert source =~ ~s|Renderer.tag("span"|

    test_source = read(root, "test/gen_probe/kotoba/nodes/status_chip_test.exs")
    assert test_source =~ ~s("paragraph")
    assert run_generated_test!(test_source) == 2

    case js_check!(root, "assets/js/kotoba/nodes/status_chip.js") do
      :skipped -> :ok
      result -> assert %{"inline" => true, "type" => "gen-probe-status-chip"} = result
    end
  end

  test "a block node", %{root: root} do
    run(root, ["Panel", "--kind", "block"])

    module = compile!(read(root, "lib/gen_probe/kotoba/nodes/panel.ex"), "panel.ex")
    assert module.kind() == :block

    assert run_generated_test!(read(root, "test/gen_probe/kotoba/nodes/panel_test.exs")) ==
             2

    case js_check!(root, "assets/js/kotoba/nodes/panel.js") do
      :skipped -> :ok
      result -> assert %{"inline" => false} = result
    end
  end

  test "refuses to replace files without --force", %{root: root} do
    run(root, ["Callout"])
    path = Path.join(root, "assets/js/kotoba/nodes/callout.js")
    File.write!(path, "// mine\n")

    assert_raise Mix.Error, ~r/These files exist: .*callout\.ex.*Give --force/s, fn ->
      run(root, ["Callout"])
    end

    assert File.read!(path) == "// mine\n"

    run(root, ["Callout", "--force"])
    assert File.read!(path) =~ "export default (lexical) =>"
  end

  test "refuses an unknown kind, a bad name and a missing name", %{root: root} do
    assert_raise Mix.Error,
                 ~s(--kind must be one of decorator, inline, block, got: "element"),
                 fn ->
                   run(root, ["Callout", "--kind", "element"])
                 end

    assert_raise Mix.Error, ~r/must be an alias/, fn -> run(root, ["callout"]) end
    assert_raise Mix.Error, ~r/Give one node name/, fn -> run(root, []) end
    refute File.exists?(Path.join(root, "assets"))
  end

  defmodule ProbeProject do
    def project, do: [app: :probe_app, version: "0.1.0"]
  end

  test "takes the app from the Mix project without --app", %{root: root} do
    Mix.Project.push(ProbeProject)

    try do
      File.cd!(root, fn -> GenNode.run(["Callout"]) end)
    after
      Mix.Project.pop()
    end

    source = read(root, "lib/probe_app/kotoba/nodes/callout.ex")
    assert source =~ "defmodule ProbeApp.Kotoba.Nodes.Callout do"
    assert source =~ ~s(type: "probe-app-callout")
  end

  test "refuses an app whose types would start with kotoba-", %{root: root} do
    for app <- ["kotoba", "kotoba_web"] do
      assert_raise Mix.Error, ~r/would start with "kotoba-", which Kotoba reserves/, fn ->
        File.cd!(root, fn -> GenNode.run(["Unknown", "--app", app]) end)
      end
    end

    # The Kotoba project itself.
    assert_raise Mix.Error, ~r/"kotoba"/, fn ->
      File.cd!(root, fn -> GenNode.run(["Callout"]) end)
    end

    refute File.exists?(Path.join(root, "assets"))
  end

  test "the generated comments show the key option" do
    [{_ex, ex}, {_js, js}, _test] =
      GenNode.files(GenNode.assigns("my_app", "Callout", :decorator))

    assert ex =~ ~s(field :ref_id, :string, key: "refId")
    assert js =~ ~s(key: "refId")
    assert js =~ "export default (lexical) =>"
  end

  test "prints the watcher and the aliases for the esbuild profile", %{root: root} do
    run(root, ["Callout"])
    output = messages()

    assert output =~
             ~S|kotoba_nodes: {Esbuild, :install_and_run, [:kotoba_nodes, ~w(--sourcemap=inline --watch)]}|

    assert output =~ ~s("esbuild kotoba_nodes")
    assert output =~ ~s("esbuild kotoba_nodes --minify")
  end
end
