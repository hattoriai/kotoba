# Extensions

An extension adds to the editor what a built-in feature has: a node, the
commands that act on it, a toolbar button and a Markdown shortcut,
registered and cleaned up together. It can also change what the editor
has already: the link form, a built-in node, and the marks over text (see
[Change what the editor has](#change-what-the-editor-has)). Each editor on
a page chooses its extensions, as it chooses its built-in features (see
the [Editing features](features.md) guide).

## Write an extension

An extension is a JavaScript module whose default export returns the
extension, or a list of extensions. Kotoba calls it once for each editor,
with the API: the editor's copies of Lexical and its packages, Kotoba's
own node classes, and `version: 1` (the version of this contract). A node
class must extend the editor's Lexical, and an extension module must not
bundle its own. A Markdown shortcut is a plain object (a transformer of
`@lexical/markdown`), so it needs no import.

| Key | What it is |
| --- | --- |
| `lexical` | `lexical` |
| `utils` | `@lexical/utils` |
| `selection` | `@lexical/selection` |
| `link` | `@lexical/link`: `LinkNode`, `$isLinkNode`, `$toggleLink`... |
| `list` | `@lexical/list` |
| `table` | `@lexical/table` |
| `richText` | `@lexical/rich-text`: `HeadingNode`, `QuoteNode`... |
| `code` | `@lexical/code-core`: `CodeNode`, `CodeHighlightNode`... |
| `mark` | `@lexical/mark`: `MarkNode`, `$wrapSelectionInMarkNode`... |
| `nodes` | Kotoba's own node classes: `AttachmentNode`, `GalleryNode`, `ImageNode`, `MentionNode`, `EmbedNode`, `FootnoteReferenceNode`, `FootnoteDefinitionNode` |
| `inline` | `$toggle` and `$isActive`: an inline element over the selected text (see [A mark over text](#a-mark-over-text)) |
| `version` | `1` |

```js
// assets/js/kotoba/extensions/callout.js
export default ({ lexical, utils, selection }) => {
  class CalloutNode extends lexical.ElementNode {
    static getType() { return "my-app-callout" }
    static clone(node) { return new CalloutNode(node.__key) }
    static importJSON(json) { return new CalloutNode().updateFromJSON(json) }
    exportJSON() { return { ...super.exportJSON(), type: "my-app-callout", version: 1 } }
    createDOM() {
      const element = document.createElement("aside")
      element.className = "my-app-callout"
      return element
    }
    updateDOM() { return false }
  }

  const $inCallout = () => {
    const current = lexical.$getSelection()
    return lexical.$isRangeSelection(current) &&
      utils.$findMatchingParent(current.anchor.getNode(), (node) => node instanceof CalloutNode) !== null
  }

  const TOGGLE_CALLOUT = lexical.createCommand("TOGGLE_CALLOUT")

  return {
    name: "callout",
    nodes: [CalloutNode],
    markdown: [{
      dependencies: [CalloutNode],
      type: "element",
      regExp: /^!!!\s/,
      export: () => null,
      replace: (parent, children) => {
        const callout = new CalloutNode()
        callout.append(...children)
        parent.replace(callout)
      },
    }],
    toolbar: [{
      command: "toggle",
      label: "Callout",
      run: (editor) => editor.dispatchCommand(TOGGLE_CALLOUT, undefined),
      isActive: $inCallout,
    }],
    register(editor, context) {
      return editor.registerCommand(TOGGLE_CALLOUT, () => {
        const current = lexical.$getSelection()
        if (!lexical.$isRangeSelection(current)) return false
        const on = !$inCallout()
        selection.$setBlocksType(current, () => (on ? new CalloutNode() : lexical.$createParagraphNode()))
        return true
      }, lexical.COMMAND_PRIORITY_EDITOR)
    },
  }
}
```

The development server has this extension, with its Elixir half, in
`dev/assets/js/kotoba/nodes/callout.js` and
`dev/lib/kotoba_dev/nodes/callout.ex`.

### The extension

| Key | |
| --- | --- |
| `name` | Required. Lower case letters, digits and `-`, unique in the editor. |
| `nodes` | Node classes. A type cannot be the type of a built-in node (of any feature), of a node module's node, or of an earlier extension's node. |
| `markdown` | Markdown shortcuts: transformers of `@lexical/markdown`. A shortcut whose `dependencies` the editor does not have is left out. |
| `toolbar` | Toolbar controls, below. |
| `blocks` | What the block handles (the `blocks` feature) do with the extension's nodes, below. |
| `insert` | Items of the insert menu, below. |
| `register(editor, context)` | Registers commands, node transforms and listeners. It returns its cleanup, a function (`mergeRegister` from `utils` joins several). |

`context` has the editor's `id`, the hook `element`, `announce(message)`,
which says a message in the editor's live region, and
`push(event, payload)`, which pushes an event to the LiveView (or to the
editor's `phx-target`) with the editor's `id` in the payload, and
`assist(action, detail)`, which asks the app for a suggestion as an item
of the Assist menu does: it pushes `kotoba:assist` with the selected text
and returns the new ref, or `null` when the editor has no `assist` (see
the [Suggestions](suggestions.md) guide).

### Toolbar controls

| Key | |
| --- | --- |
| `command` | Required. Lower case letters, digits and `-`, unique in the extension. The toolbar knows the control as `<name>:<command>`, for example `callout:toggle`. |
| `label` | Required. The accessible name and the title of the button. |
| `run(editor)` | Required. Runs in an update of the editor, with the selection that the person sees. |
| `group` | The toolbar group; the default is the extension's name. |
| `icon()` | Returns an element (an SVG) for the button; without it, the button shows the label. |
| `isActive()` | `aria-pressed`, read from the editor state. With it, the button is a toggle, and the live region says "Callout on" or "Callout off". |
| `isVisible()` | Whether the button shows, read from the editor state. |
| `isEnabled()` | Whether the button can act now (`aria-disabled` when not). |
| `done` | What the live region says when the command has run, for a control that is not a toggle. |

The controls are part of the toolbar: one tab stop, the arrow keys, Home,
End, and Alt+F10 from the editor. The default toolbar puts them before the
History group. In a custom toolbar, place one by its command:

```heex
<.kotoba_toolbar>
  <:button command="bold"><.icon name="hero-bold" /></:button>
  <:button command="callout:toggle" label="Callout"><.icon name="hero-information-circle" /></:button>
</.kotoba_toolbar>
```

### Blocks

With the `blocks` feature (see the [Editing features](features.md)
guide), every top-level block has a handle and a menu. An extension says
how a block of its node takes part:

```javascript
blocks: [{ type: "callout", label: "Callout", create: () => new CalloutNode() }],
```

| Key | |
| --- | --- |
| `type` | Required. The node type. |
| `label` | The words of the item in the menu's Turn into. |
| `create()` | Makes an empty block of the type. With `label`, Turn into offers it, and turns a block of the type into the others: its text moves into the new block. |
| `handle` | `false`: a block of the type has no handle (a node that handles itself). |

A block of a type with no `create` has a handle, and its menu has
Duplicate, Delete and Copy a link, with no Turn into.

### Insert items

An editor with an insert menu (a prompt with `insert: :command`, see the
[Prompts](prompts.md) guide) has the extensions' items, where its
`:items` has `:extensions`. A block with a `label` and a `create` is one
already: the callout appears as Callout, with no code. Other commands are
insert items:

```javascript
insert: [{ command: "note", label: "Note", group: "Callouts", keywords: ["info"], run: (editor) => editor.dispatchCommand(INSERT_NOTE_COMMAND, undefined) }],
```

| Key | |
| --- | --- |
| `command` | Required. Lower case letters, digits and `-`, unique in the extension. The menu knows the item as `<name>:<command>`, for example `callout:note`, and an app's item can name it. |
| `label` | Required. The item's words in the menu. |
| `run(editor)` | Required. Runs in an update of the editor, with the caret where the trigger was (the trigger and the query are removed). |
| `group` | The menu's group; the default is the extension's name. |
| `keywords` | More words that find the item. |
| `icon()` | Returns an element (an SVG) for the item. |

### The context

`register(editor, context)` gets the context, and so do the link hooks
below:

| Key | |
| --- | --- |
| `id` | The editor's id: every event from the editor has it. |
| `element` | The hook element. |
| `announce(message)` | Says a message in the editor's live region. |
| `push(event, payload)` | Pushes an event to the LiveView (or the `phx-target` component), with the editor's `id` and `v: 1`. |
| `request(event, payload)` | Pushes an event as `push` does, and returns a promise of the reply (`{:reply, map, socket}`). It rejects when the editor is destroyed first, or after 10 seconds with no reply. |
| `assist(action, detail)` | Asks the app for a suggestion for the selection, as the Assist menu does. |

```elixir
def handle_event("my-app:search", %{"query" => query}, socket) do
  {:reply, %{results: MyApp.search(query)}, socket}
end
```

## Change what the editor has

TipTap lets an app `extend` a node or own a panel. A Kotoba extension does
the same with these points. Kotoba itself adds no feature of the app: the
extension has it.

### The link form

`link` in an extension changes the link form (the Link button, Cmd/Ctrl+K
and the link card's Edit):

```js
export default ({ lexical }) => ({
  name: "page-links",
  link: {
    // Suggestions for the words typed in the form.
    async suggest(query, context) {
      const reply = await context.request("pages:search", { query })
      return reply.pages // [{ url: "/pages/5", label: "Kotoba", detail: "Open source" }]
    },
  },
})
```

* `suggest(query, context)` returns suggestions, or a promise of them,
  for the words typed (not for a URL: text that starts with a scheme, `/`,
  `#` or `?`). A suggestion has `url`, `label`, and optionally `detail` (a
  second line) and `icon()` (an element). The form lists the suggestions
  of every extension under its input, at most 10: the input becomes a
  combobox, the arrow keys move in the list, Enter or a click applies the
  suggestion's URL, and Escape closes the list (a second Escape closes the
  form). For words, the first suggestion is selected, so Enter takes it;
  for text like a host name (`example.com`), none is, so Enter applies the
  text as a URL.
* `open(request, context)` opens a link form of the extension's own in
  place of Kotoba's, and returns `true`. The first extension that returns
  `true` has the form; when all return `false`, Kotoba's opens. The
  request has the `url` of the link at the selection (or `null`), the
  selected `text`, and `apply(url)`: it puts the link on the request's
  selection (or removes it, with `null`), even when the selection moved
  meanwhile, and gives the focus back to the editor. It returns `false`,
  and applies nothing, for a URL that the editor's link schemes refuse.

The link that the form makes is a built-in link with that URL. To render
it otherwise on the server (a page's path now, or only its text when the
page is gone), give the link an override; see the next section.

### A built-in node

An extension can keep its own values on a built-in node, and change how
it shows, in the editor and on the server:

* **Its values:** Lexical's NodeState. `lexical.createState(key, {parse})`
  makes a state; `lexical.$setState(node, state, value)` and
  `lexical.$getState(node, state)` write and read it. The node's JSON
  keeps it under `"$"`, and the server keeps it, as it keeps any key that
  a node does not declare.
* **Its DOM in the editor:** a mutation listener of the node class,
  `editor.registerMutationListener(api.link.LinkNode, listener)`, or a
  transform (`editor.registerNodeTransform`). The classes are in the API:
  Lexical's packages and `api.nodes`.
* **Its HTML, text and Markdown:** a `Kotoba.Node.Override` on the server.
  It renders the node, and `Kotoba.Node.Override.state/3` reads its state.

```js
export default ({ lexical, utils, link }) => {
  const target = lexical.createState("target", { parse: (v) => (typeof v === "string" ? v : undefined) })
  const $link = () => {
    const selection = lexical.$getSelection()
    return lexical.$isRangeSelection(selection) ? utils.$findMatchingParent(selection.anchor.getNode(), link.$isLinkNode) : null
  }

  return {
    name: "new-tab",
    toolbar: [{
      command: "toggle",
      label: "Open in a new tab",
      run: (editor) => editor.update(() => {
        const node = $link()
        if (node) lexical.$setState(node, target, lexical.$getState(node, target) ? undefined : "_blank")
      }),
      isActive: () => { const node = $link(); return node !== null && lexical.$getState(node, target) === "_blank" },
      isEnabled: () => $link() !== null,
    }],
  }
}
```

```elixir
defmodule MyApp.Links do
  use Kotoba.Node.Override, of: Kotoba.Nodes.Link

  alias Kotoba.Renderer

  @impl Kotoba.Node.Override
  def render_html(node, opts) do
    if Kotoba.Node.Override.state(node, "target") == "_blank",
      do: Renderer.tag("a", [href: node.url, target: "_blank", rel: "noopener"], Renderer.html_children(node, opts)),
      else: Kotoba.Nodes.Link.render_html(node, opts)
  end
end

# config/config.exs
config :kotoba, overrides: [MyApp.Links]
```

See [Rendering](rendering.md#another-rendering-of-a-node) for where an
override applies.

### A mark over text

Lexical has a fixed set of text formats (bold, italic...). A mark of the
app (a spoiler, a citation, a term) is an inline element node over the
text, as a link is. Its class extends `lexical.ElementNode` with
`isInline()` true, and `api.inline` puts the selected text in it, or takes
it out:

```js
export default ({ lexical, inline }) => {
  class SpoilerNode extends lexical.ElementNode {
    static getType() { return "my-app-spoiler" }
    static clone(node) { return new SpoilerNode(node.__key) }
    static importJSON(json) { return new SpoilerNode().updateFromJSON(json) }
    exportJSON() { return { ...super.exportJSON(), type: "my-app-spoiler", version: 1 } }
    createDOM() { const span = document.createElement("span"); span.className = "my-app-spoiler"; return span }
    updateDOM() { return false }
    isInline() { return true }
    canBeEmpty() { return false }
    canInsertTextBefore() { return false }
    canInsertTextAfter() { return false }
  }

  return {
    name: "spoiler",
    nodes: [SpoilerNode],
    toolbar: [{
      command: "toggle",
      label: "Spoiler",
      run: (editor) => editor.update(() => inline.$toggle(SpoilerNode, () => new SpoilerNode())),
      isActive: () => inline.$isActive(SpoilerNode),
    }],
  }
}
```

* `inline.$toggle(Klass, create)` takes the selected text out of its
  elements of `Klass` when all of it is in one, else puts it in new ones
  made by `create`: one for each run of text with the same parent.
* `inline.$isActive(Klass)` says whether all the selected text is in one.

The server half is a `Kotoba.Node` with `kind: :inline, element: true`.
For a mark with ids (comments, for example), `api.mark` has Lexical's
`MarkNode` and `$wrapSelectionInMarkNode`.

### The selection menu

A toolbar control of an extension can be in the selection menu too: name
it as `<extension>:<command>`, for example
`selection_menu={~w(bold italic link spoiler:toggle)}` (see the
[Editing features](features.md) guide).

## Serve the module and give it to the editor

The editor loads the module with `import()`, so serve it as an ES module.
Add an esbuild profile in `config/config.exs`, as for node modules (see
the [Custom nodes](custom_nodes.md) guide):

```elixir
config :esbuild,
  kotoba_extensions: [
    args:
      ~w(js/kotoba/extensions/*.js --bundle --format=esm --target=es2022 --outdir=../priv/static/assets/kotoba/extensions),
    cd: Path.expand("../assets", __DIR__)
  ]
```

with a watcher in `config/dev.exs` and the profile in the `assets.build`
and `assets.deploy` aliases, as the Custom nodes guide shows. Then give
the module's URL to the editors that have it:

```heex
<.kotoba field={@form[:body]} extensions={[~p"/assets/kotoba/extensions/callout.js"]} />
```

Do not import `lexical` in the module: the default export gets it.

The Elixir half of a node is a `Kotoba.Node` module in
`config :kotoba, nodes: [...]`, as for any app node. Insert a node from
the server with `Kotoba.Live.insert_node/3`.

## Order, failures and cleanup

* The built-in features register first, then the extensions in the order
  of `extensions`; the Markdown shortcuts of all of them register last.
  Every `register` runs before the document loads.
* A module that does not load, an extension that is not valid, a name or a
  node type that is taken, and a `register` that throws are logged in the
  console, and the editor mounts with the rest. A toolbar control whose
  `run` or state function throws is logged, and the others work.
* When LiveView removes the editor, the cleanups run in the reverse order.
  When it mounts it again, Kotoba calls the module's default export again:
  an extension keeps its state in that function, not in the module, so two
  editors and two mounts do not share it.
