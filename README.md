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

Add the editor to a form with `<.kotoba>`:

```heex
<.form for={@form} id="post-form" phx-change="validate" phx-submit="save">
  <.input field={@form[:title]} label="Title" />
  <.kotoba field={@form[:body]} placeholder="Write your post..." />
  <.button>Save</.button>
</.form>
```

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

The toolbar icons are from Lucide (https://lucide.dev), ISC licence.
