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

Run `mix deps.get`.

Import the editor hook in `assets/js/app.js` and add it to your hooks:

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
config :kotoba, storage: Kotoba.Storage.Local

config :kotoba, Kotoba.Storage.Local,
  root: "priv/uploads/kotoba",
  url_prefix: "/uploads/kotoba"
```

```elixir
# In the endpoint, before the router:
plug Kotoba.Storage.Local.Plug
```

For S3 or another store, write a module with the three `Kotoba.Storage`
callbacks (`put/3`, `url/1`, `delete/1`) and set `config :kotoba, storage:`
to it. The `Kotoba.Storage` docs have an example.

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

## License

Kotoba is released under the Apache License, Version 2.0. See `LICENSE` for
the full text.

The toolbar icons are from Lucide (https://lucide.dev), ISC licence. See `NOTICE`.
