defmodule Mix.Tasks.Kotoba.Gen.Node do
  @shortdoc "Generates an app node: the Elixir module, the JavaScript module and a test"

  @moduledoc """
  Generates the two halves of an app-defined node, and a test.

      $ mix kotoba.gen.node Callout
      $ mix kotoba.gen.node Pointer --kind inline

  For an app `:my_app`, `mix kotoba.gen.node Callout` writes:

    * `lib/my_app/kotoba/nodes/callout.ex` - `MyApp.Kotoba.Nodes.Callout`,
      a `Kotoba.Node` of type `"my-app-callout"` with a `label` field and
      its render callbacks. The type starts with the app name, so it
      cannot be the type of a built-in node.
    * `assets/js/kotoba/nodes/callout.js` - the Lexical node for the editor.
      The module exports a default factory, `(lexical) => class`, so that
      the class extends the editor's own copy of Lexical.
    * `test/my_app/kotoba/nodes/callout_test.exs` - a test that parses,
      renders and reads the text of a document with the node.

  Then it prints the config line and the component attribute that register
  the node.

  ## Options

    * `--kind` - `decorator` (the default), `inline` or `block`. An inline
      node goes in a paragraph; a block node and a decorator go in the
      document root.
    * `--app` - the application name. The default is the `:app` of the
      Mix project.
    * `--force` - replaces files that exist. Without it, the task stops
      when one of the files exists.
  """

  use Mix.Task

  @kinds ~w(decorator inline block)

  @impl Mix.Task
  def run(argv) do
    {opts, args} =
      OptionParser.parse!(argv, strict: [kind: :string, app: :string, force: :boolean])

    assigns = opts |> app() |> assigns(name(args), kind(opts))
    files = files(assigns)

    existing = for {path, _content} <- files, File.exists?(path), do: path

    if existing != [] and not Keyword.get(opts, :force, false) do
      Mix.raise("""
      These files exist: #{Enum.join(existing, ", ")}.
      Give --force to replace them.\
      """)
    end

    for {path, content} <- files do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      Mix.shell().info([:green, "* creating ", :reset, path])
    end

    Mix.shell().info(instructions(assigns))
  end

  defp name([name]) do
    if Regex.match?(~r/^[A-Z][A-Za-z0-9]*$/, name),
      do: name,
      else:
        Mix.raise(
          "The node name must be an alias such as Callout or CalloutBox, got: #{inspect(name)}"
        )
  end

  defp name(_args), do: Mix.raise("Give one node name, for example: mix kotoba.gen.node Callout")

  defp kind(opts) do
    case Keyword.get(opts, :kind, "decorator") do
      "decorator" -> :decorator
      "inline" -> :inline
      "block" -> :block
      kind -> Mix.raise("--kind must be one of #{Enum.join(@kinds, ", ")}, got: #{inspect(kind)}")
    end
  end

  defp app(opts) do
    app =
      case Keyword.fetch(opts, :app) do
        {:ok, app} ->
          app

        :error ->
          to_string(Mix.Project.config()[:app] || Mix.raise("Give the app name with --app"))
      end

    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, app),
      do: app,
      else:
        Mix.raise(
          "The app name must be a lower-case Elixir atom such as my_app, got: #{inspect(app)}"
        )
  end

  @doc false
  @spec assigns(String.t(), String.t(), :decorator | :inline | :block) :: map()
  def assigns(app, name, kind) do
    file = Macro.underscore(name)
    base = Macro.camelize(app)

    %{
      app: app,
      name: name,
      kind: kind,
      file: file,
      module: "#{base}.Kotoba.Nodes.#{name}",
      test_module: "#{base}.Kotoba.Nodes.#{name}Test",
      type: String.replace(app, "_", "-") <> "-" <> String.replace(file, "_", "-"),
      class: name <> "Node",
      inline: kind == :inline,
      tag: if(kind == :inline, do: "span", else: "div"),
      ex_path: Path.join(["lib", app, "kotoba", "nodes", file <> ".ex"]),
      js_path: Path.join(["assets", "js", "kotoba", "nodes", file <> ".js"]),
      test_path: Path.join(["test", app, "kotoba", "nodes", file <> "_test.exs"]),
      url: "/assets/kotoba/nodes/#{file}.js"
    }
  end

  @doc false
  @spec files(map()) :: [{String.t(), String.t()}]
  def files(assigns) do
    [
      {assigns.ex_path, assigns |> elixir_module() |> format()},
      {assigns.js_path, js_module(assigns)},
      {assigns.test_path, assigns |> test_module() |> format()}
    ]
  end

  # `field` is written without parentheses, as `Kotoba.Node` documents it.
  defp format(source) do
    source
    |> Code.format_string!(locals_without_parens: [field: 2, field: 3])
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  defp elixir_module(b) do
    """
    defmodule #{b.module} do
      @moduledoc \"\"\"
      The `#{b.type}` node, kind `#{inspect(b.kind)}`.

      Its editor half is `#{b.js_path}`,
      whose `exportJSON()` writes the JSON keys of the fields below.
      \"\"\"
      use Kotoba.Node, type: "#{b.type}", kind: #{inspect(b.kind)}

      alias Kotoba.Renderer

      field :label, :string, required: true

      @impl Kotoba.Node
      def render_html(node, _opts) do
        Renderer.tag("#{b.tag}", [class: "#{b.type}"], node.label)
      end

      @impl Kotoba.Node
      def render_text(node, _opts), do: node.label

      @impl Kotoba.Node
      def render_markdown(node, _opts), do: Renderer.escape_markdown(node.label)
    end
    """
  end

  defp js_module(b) do
    """
    // The editor half of #{b.module} (type "#{b.type}").
    //
    // Kotoba calls this factory with the editor's copy of Lexical, so the
    // class extends the same DecoratorNode as the built-in nodes. The keys of
    // exportJSON() are the JSON keys of the fields of the Elixir module.
    // decorate() returns an HTMLElement, which Kotoba puts in the editor.
    export default (lexical) =>
      class #{b.class} extends lexical.DecoratorNode {
        static getType() {
          return "#{b.type}"
        }

        static clone(node) {
          return new #{b.class}(node.__label, node.__key)
        }

        static importJSON(json) {
          return new #{b.class}(String(json.label ?? ""))
        }

        constructor(label = "", key) {
          super(key)
          this.__label = label
        }

        exportJSON() {
          return {type: "#{b.type}", version: 1, label: this.getLatest().__label}
        }

        createDOM() {
          const element = document.createElement(this.isInline() ? "span" : "div")
          element.className = "#{b.type}"
          element.contentEditable = "false"
          return element
        }

        updateDOM() {
          return false
        }

        decorate() {
          const element = document.createElement("span")
          element.textContent = this.getLatest().__label
          return element
        }

        getTextContent() {
          return this.getLatest().__label
        }

        isInline() {
          return #{b.inline}
        }

        isKeyboardSelectable() {
          return true
        }
      }
    """
  end

  defp test_module(b) do
    node = ~s(%{"type" => "#{b.type}", "version" => 1, "label" => "Hello"})

    children =
      if b.inline,
        do: ~s([%{"type" => "paragraph", "children" => [#{node}]}]),
        else: "[#{node}]"

    html =
      if b.inline,
        do: ~s(<p><span class="#{b.type}">Hello</span></p>),
        else: ~s(<div class="#{b.type}">Hello</div>)

    """
    defmodule #{b.test_module} do
      use ExUnit.Case, async: true

      alias Kotoba.{Document, Renderer}
      alias #{b.module}

      @document %{
        "kotoba" => 1,
        "lexical" => "0.51",
        "root" => %{"type" => "root", "children" => #{children}}
      }

      test "parses, renders and reads the text of a document with the node" do
        assert {:ok, doc} = Document.parse(@document, nodes: [#{b.name}])
        assert [%#{b.name}{label: "Hello"}] = Document.reduce(doc, [], &collect/2)

        assert doc |> Renderer.to_html() |> Phoenix.HTML.safe_to_string() ==
                 ~s(#{html})

        assert Renderer.to_text(doc) == "Hello"
        assert Renderer.to_markdown(doc) == "Hello"
        assert {:ok, ^doc} = doc |> Document.to_json() |> Document.parse(nodes: [#{b.name}])
      end

      test "escapes the label" do
        doc = put_in(@document, label_path(), "<b>bold</b>")
        assert {:ok, doc} = Document.parse(doc, nodes: [#{b.name}])
        html = doc |> Renderer.to_html() |> Phoenix.HTML.safe_to_string()
        assert html =~ "&lt;b&gt;bold&lt;/b&gt;"
        refute html =~ "<b>"
      end

      defp collect(%#{b.name}{} = node, acc), do: acc ++ [node]
      defp collect(_node, acc), do: acc

      defp label_path do
        #{if b.inline, do: ~s|["root", "children", Access.at(0), "children", Access.at(0), "label"]|, else: ~s|["root", "children", Access.at(0), "label"]|}
      end
    end
    """
  end

  defp instructions(b) do
    """

    Register the node for parsing and rendering in config/config.exs:

        config :kotoba, nodes: [#{b.module}]

    Give the editor the JavaScript half:

        <.kotoba field={@form[:body]} nodes={[{#{b.module}, ~p"#{b.url}"}]} />

    The editor loads #{b.url} with import(), so serve it as an ES module.
    For example, add an esbuild profile in config/config.exs:

        config :esbuild,
          kotoba_nodes: [
            args: ~w(js/kotoba/nodes/*.js --bundle --format=esm --target=es2022 --outdir=../priv/static/assets/kotoba/nodes),
            cd: Path.expand("../assets", __DIR__)
          ]

    and run it in the "assets.build" and "assets.deploy" aliases
    ("esbuild kotoba_nodes") and in the endpoint watchers of config/dev.exs.
    """
  end
end
