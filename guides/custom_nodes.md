# Custom nodes

An app can add its own nodes to the document, for example a callout, a
status chip or a link to a record. A node has two halves:

* a `Kotoba.Node` module in Elixir. It reads the node from the JSON,
  checks it, and renders it as HTML, text and Markdown.
* a JavaScript module with the Lexical node class, for the editor.

## Generate a node

```sh
mix kotoba.gen.node Callout                  # a decorator (the default)
mix kotoba.gen.node StatusChip --kind inline
mix kotoba.gen.node Panel --kind block
```

For an app `:my_app`, `mix kotoba.gen.node Callout` writes:

* `lib/my_app/kotoba/nodes/callout.ex`: `MyApp.Kotoba.Nodes.Callout`, of
  type `"my-app-callout"`, with a `label` field.
* `assets/js/kotoba/nodes/callout.js`: the Lexical node.
* `test/my_app/kotoba/nodes/callout_test.exs`: a test that parses, renders
  and reads the text of a document with the node.

The type starts with the app name, so it cannot be the type of a built-in
node. `--module` gives another module name, and `--out` another directory.
See `Mix.Tasks.Kotoba.Gen.Node`.

The kinds:

* `decorator`: a node with no editable text in it, for example a card. It
  goes in the root of the document.
* `inline`: a node in a line of text, for example a chip. It goes in a
  paragraph.
* `block`: a block in the root of the document.

## The Elixir half

```elixir
defmodule MyApp.Kotoba.Nodes.Callout do
  use Kotoba.Node, type: "my-app-callout", kind: :decorator

  alias Kotoba.Renderer

  field :label, :string, required: true
  field :tone_name, :string, key: "toneName", default: "info", in: ~w(info warning)

  @impl Kotoba.Node
  def render_html(node, _opts) do
    Renderer.tag("div", [class: "my-app-callout", "data-tone": node.tone_name], node.label)
  end

  @impl Kotoba.Node
  def render_text(node, _opts), do: node.label

  @impl Kotoba.Node
  def render_markdown(node, _opts), do: Renderer.escape_markdown(node.label)
end
```

`field/3` declares one attribute of the JSON. The types are `:string`,
`:integer`, `:boolean`, `:map` and `{:array, type}`.

A field with more than one word needs a camelCase JSON key, as Lexical
writes it: `field :tone_name, :string, key: "toneName"`. The JavaScript
half uses the same key in `exportJSON()` and `importJSON()`. Without
`key:`, the JSON key is the field name, `"tone_name"`.

`render_html/2` returns safe HTML: a `~H` template, `Kotoba.Renderer.tag/3`,
or `{:safe, iodata}`. A plain string is escaped. Use
`Kotoba.Renderer.escape_markdown/1` for the Markdown of text, so that the
text cannot make Markdown syntax, a heading or a list included.

`Kotoba.Renderer.tag/3` escapes the attribute values and the content, but
not the tag name or the attribute names, and it does not check URLs. So:

* keep the tag and attribute names literal in your code, and never take
  them from the node's fields;
* pass each `href` or `src` through `Kotoba.Sanitizer.link_url/2` and
  render no link when it returns `nil`. For a link, also check the policy:
  render the link only when `Kotoba.Renderer.policy(opts).links` is true,
  so that the `:untrusted` policy gives text.

To add `.formatter.exs` support for `field` without parentheses, add
`:kotoba` to `import_deps`.

## The JavaScript half

```js
// assets/js/kotoba/nodes/callout.js
export default (lexical) =>
  class CalloutNode extends lexical.DecoratorNode {
    static getType() { return "my-app-callout" }
    static clone(node) { return new CalloutNode(node.__label, node.__key) }
    static importJSON(json) { return new CalloutNode(String(json.label ?? "")) }
    constructor(label = "", key) { super(key); this.__label = label }
    exportJSON() { return {type: "my-app-callout", version: 1, label: this.getLatest().__label} }
    createDOM() { /* the element that holds the node */ }
    updateDOM() { return false }
    decorate() { /* returns an HTMLElement, which Kotoba puts in the editor */ }
  }
```

The module exports a factory as its default export. The editor calls the
factory with its own copy of Lexical, so the class extends the same
`DecoratorNode` as the built-in nodes. A class that extends another copy
of Lexical (a module that bundles `lexical` itself) is refused, with an
error in the browser console. `decorate()` returns an `HTMLElement`.

The editor refuses a node whose type is a built-in type, or a module that
does not load. It logs the error and mounts with the other nodes.

## Build and serve the module

The editor loads the module with `import()`, so serve it as an ES module.
Add an esbuild profile in `config/config.exs`:

```elixir
config :esbuild,
  kotoba_nodes: [
    args:
      ~w(js/kotoba/nodes/*.js --bundle --format=esm --target=es2022 --outdir=../priv/static/assets/kotoba/nodes),
    cd: Path.expand("../assets", __DIR__)
  ]
```

a watcher in the endpoint config of `config/dev.exs`:

```elixir
watchers: [
  kotoba_nodes: {Esbuild, :install_and_run, [:kotoba_nodes, ~w(--sourcemap=inline --watch)]},
  # ...
]
```

and the profile in the aliases of `mix.exs`:

```elixir
"assets.build": [..., "esbuild kotoba_nodes"],
"assets.deploy": [..., "esbuild kotoba_nodes --minify", "phx.digest"]
```

Do not import `lexical` in the module: the factory gets it.

## Register the node

```elixir
# config/config.exs
config :kotoba, nodes: [MyApp.Kotoba.Nodes.Callout]
```

```heex
<.kotoba
  field={@form[:body]}
  nodes={[{MyApp.Kotoba.Nodes.Callout, ~p"/assets/kotoba/nodes/callout.js"}]}
/>
```

The two places do different things:

* `config :kotoba, nodes:` is the node registry of the server.
  `Kotoba.Content.cast/1` uses it when it parses and renders the cache,
  and `Kotoba.Document.parse/2` uses it by default.
* The `nodes` attribute of `Kotoba.Components.kotoba/1` gives the editor
  the URL of the JavaScript half.

Put every node that stored content uses in the config. A node that is
only in the component, and not in the config, is an unknown node when the
content is cast. The document keeps it with all its attributes, but the
cached HTML has only an empty `span.kotoba-unknown` for it. To render it,
give the node when you render:

```elixir
Kotoba.Content.rerender(content, nodes: [MyApp.Kotoba.Nodes.Callout])
```

```heex
<.kotoba_content content={@post.body} nodes={[MyApp.Kotoba.Nodes.Callout]} />
```

An app node cannot have a reserved type (a built-in type,
`"kotoba-unknown"` or `"kotoba-upload"`, see
`Kotoba.Nodes.reserved_types/0`): the registry
raises `ArgumentError`, as the editor refuses it. Do not start a type with
`kotoba-`; the generator refuses an app name that would do this.

## Insert a node

The toolbar has no button for app nodes. Insert one from the server, for
example from a button of your own:

```elixir
def handle_event("add_callout", _params, socket) do
  node = %MyApp.Kotoba.Nodes.Callout{label: "Read this first"}
  {:noreply, Kotoba.Live.insert_node(socket, "post-body", node)}
end
```

`Kotoba.Live.insert_node/4` checks the node with its `validate/1` and
sends its JSON. The editor puts it at the selection.

## After a change of a node module

The cache of stored content does not change when you add, remove or
change a node module. Use `Kotoba.Content.rerender/2` to bring stored rows
up to date, for example in a migration task. See the
[Limits](limits.md) guide.
