# Kotoba

Kotoba (言葉, "words") is a rich text package for Phoenix. Kotoba gives your
app a rich text editor, a content type for your schemas, and safe rendering
for the stored content. The editor is a prebuilt JavaScript bundle. Your app
does not need a Node.js build step to use it. You add the hook, you add one
CSS file, and you get a full editor: text formatting, lists, links, code
blocks, file attachments, and @-mentions.

## Status

Kotoba 0.1 is in development. The API can change before the first release.

## Install

Add `kotoba` to the deps in your `mix.exs` file:

```elixir
def deps do
  [
    {:kotoba, "~> 0.1"}
  ]
end
```

Run `mix deps.get`, then `mix kotoba.install`. The installer adds the hook
to `assets/js/app.js`, the style sheet to `assets/css/app.css` and the
storage adapter to `config/config.exs`, and prints what it changed. Run it
with `--dry-run` to see the changes first. It changes nothing that is
already there, so you can run it again.

To make the same changes by hand, import the editor hook in `assets/js/app.js` and add it to your hooks:

```js
import { Kotoba } from "kotoba"

let Hooks = {}
Hooks.Kotoba = Kotoba

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken }
})
```

Import the editor CSS in `assets/css/app.css`:

```css
@import "../../deps/kotoba/priv/static/kotoba.css";
```

## Usage

### Schema field

Store rich text as a `Kotoba.Content` field on an Ecto schema:

```elixir
defmodule MyApp.Blog.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :title, :string
    field :body, Kotoba.Content

    timestamps()
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :body])
    |> validate_required([:title, :body])
  end
end
```

### Form component

Import the components (for example in the `html_helpers` of your web
module) and add the editor to a form with `<.kotoba>`:

```elixir
import Kotoba.Components
```

```heex
<.form for={@form} id="post-form" phx-change="validate" phx-submit="save">
  <.input field={@form[:title]} label="Title" />
  <label id="post-body-label">Body</label>
  <.kotoba
    field={@form[:body]}
    id="post-body"
    label_id="post-body-label"
    placeholder="Write your post..."
  />
  <.button>Save</.button>
</.form>
```

The editor writes the document to a hidden input, so the form posts it with
the other fields. In a LiveComponent, add `phx-target={@myself}`.

### Mentions

Give the editor a prompt list. The trigger `@` opens a menu with the results
of the first function:

```heex
<.kotoba field={@form[:body]} id="post-body" prompts={@prompts} />
```

```elixir
def mount(_params, _session, socket) do
  {:ok, assign(socket, prompts: [people: &MyApp.People.search/1])}
end

def handle_event("kotoba:prompt", params, socket) do
  {:noreply, Kotoba.Live.handle_prompt(socket, params, socket.assigns.prompts)}
end
```

`MyApp.People.search/1` gets the query and returns items such as
`%{id: 1, label: "Ada Lovelace"}`. See `Kotoba.Prompts`.

### Attachments

Allow a LiveView upload, give it to the editor, and store the finished
files with `Kotoba.Live.consume_uploads/4`:

```elixir
socket =
  allow_upload(socket, :attachments,
    accept: ~w(.png .jpg .gif .webp .pdf),
    max_file_size: 10_000_000,
    auto_upload: true,
    progress: &handle_progress/3
  )

defp handle_progress(:attachments, %{done?: true}, socket),
  do: {:noreply, Kotoba.Live.consume_uploads(socket, :attachments, "post-body")}

defp handle_progress(:attachments, _entry, socket), do: {:noreply, socket}
```

```heex
<.kotoba field={@form[:body]} id="post-body" uploads={@uploads.attachments} />
```

Call `Kotoba.Live.consume_uploads/4` from the form's `phx-change` handler
too, so that a file that fails validation loses its placeholder.

The files go to a `Kotoba.Storage` adapter. The local adapter keeps them on
disk, and `Kotoba.Storage.Local.Plug` serves them:

```elixir
# config/config.exs
config :kotoba, storage: Kotoba.Storage.Local

# config/runtime.exs: an absolute path outside the release
config :kotoba, Kotoba.Storage.Local,
  root: System.get_env("KOTOBA_UPLOADS", "/var/lib/my_app/uploads"),
  url_prefix: "/uploads/kotoba"
```

```elixir
# In the endpoint, before the router:
plug Kotoba.Storage.Local.Plug
```

Kotoba keeps only a content type that the bytes of the file prove (images,
PDF, plain text, ZIP and Office files); every other file is stored as
`application/octet-stream` with a `.bin` key. Serve uploads with
`X-Content-Type-Options: nosniff` and `Content-Disposition: attachment` for
everything that is not an image or a PDF, as `Kotoba.Storage.Local.Plug`
does.

For S3 or another store, write a module with the three `Kotoba.Storage`
callbacks (`put/3`, `url/1`, `delete/1`) and set `config :kotoba, storage:`
to it. The `Kotoba.Storage` docs have an example.

### Custom nodes

An app can add its own nodes to the editor. A node has two halves: a
`Kotoba.Node` module, which reads, checks and renders the node on the
server, and a JavaScript module with the Lexical node for the editor.
`mix kotoba.gen.node` writes both, and a test:

```sh
mix kotoba.gen.node Callout                # a decorator (the default)
mix kotoba.gen.node StatusChip --kind inline
```

For an app `:my_app`, `mix kotoba.gen.node Callout` writes
`lib/my_app/kotoba/nodes/callout.ex` (`MyApp.Kotoba.Nodes.Callout`, type
`"my-app-callout"`), `assets/js/kotoba/nodes/callout.js` and
`test/my_app/kotoba/nodes/callout_test.exs`. Register the node for parsing
and rendering, and give the editor its JavaScript module:

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

The editor loads the module with `import()`, so serve it as an ES module,
for example with an esbuild profile
(`js/kotoba/nodes/*.js --bundle --format=esm --outdir=../priv/static/assets/kotoba/nodes`).
The module exports a factory, `export default (lexical) => class ...`, so
the node class extends the editor's own copy of Lexical. A node cannot
have the type of a built-in node: the editor refuses it, and
`Kotoba.Nodes.registry/1` raises `ArgumentError`.

Put the node in `config :kotoba, nodes:`: `Kotoba.Content` renders its
cache when it casts, with the configured nodes. A node that is not
configured stays in the document as an unknown node, and renders as an
empty `span.kotoba-unknown` until the content is rendered again with
`Kotoba.Content.rerender(content, nodes: [...])`, or through
`<.kotoba_content nodes={...}>`.

### Render component

Render stored content as safe HTML with `<.kotoba_content>`:

```heex
<.kotoba_content content={@post.body} />
```

`<.kotoba_content>` renders the content's cached HTML. Kotoba sanitizes all
rendered output, so raw HTML in the stored content never reaches the page.

## Development

The editor source is TypeScript in `assets/`. `mix kotoba.build` (in the
`:dev` environment) runs `npm ci` in `assets/` when needed, bundles the
editor with esbuild and copies the style sheets into `priv/static`. The
built files are not in the repository; the Hex package includes them.

`mix dev` starts a development server on http://localhost:4099 (set `PORT`
for another port). It runs `dev.exs`: a Phoenix endpoint with the editor in
a form, the `@` prompt, uploads to `tmp/uploads`, an app node made with
`mix kotoba.gen.node` (in `dev/`), and buttons that send each server event.
esbuild watchers rebuild the bundle and the node modules (into
`tmp/dev/nodes`, not into the package), and the page reloads when they
change. Restart `mix dev` after a change in `dev/lib`. Run
`mix kotoba.build` once before the first `mix dev`, for the style sheets.

The browser tests in `e2e/` use Playwright with Chromium. Install the
browser once:

```sh
cd e2e && npm ci && npx playwright install chromium
```

Then run them from the repository root with `mix test.e2e`. It runs
`npm ci` in `e2e/` when `e2e/node_modules` is missing, and `npm test`,
which builds the bundle and starts its own development server, without
watchers, on port 4098 (set `E2E_PORT` for another port). A `mix dev` on
port 4099 can keep running.

## License

Kotoba is released under the Apache License, Version 2.0. See `LICENSE` for
the full text.

The toolbar icons are from Lucide (https://lucide.dev), ISC licence. See `NOTICE`.
