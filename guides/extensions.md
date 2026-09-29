# Extensions

An extension adds to the editor what a built-in feature has: a node, the
commands that act on it, a toolbar button and a Markdown shortcut,
registered and cleaned up together. Each editor on a page chooses its
extensions, as it chooses its built-in features (see the
[Editing features](features.md) guide).

## Write an extension

An extension is a JavaScript module whose default export returns the
extension, or a list of extensions. Kotoba calls it once for each editor,
with an object that has the editor's copies of `lexical`, `@lexical/utils`
and `@lexical/selection`, and `version: 1` (the version of this
contract). A node class must extend the editor's Lexical, and an
extension module must not bundle its own. A Markdown shortcut is a plain object (a transformer of
`@lexical/markdown`), so it needs no import.

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
