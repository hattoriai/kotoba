# Quickstart

This guide adds a rich-text field to a Phoenix 1.8 app with LiveView 1.2.
At the end, a LiveView form has a Kotoba editor, the schema stores the
document, and a page shows the stored content as safe HTML.

Your app does not run Node.js for Kotoba. The Hex package has the built
editor bundle, and your esbuild profile imports it from `deps/`.

## 1. Add the dependency

In `mix.exs`:

```elixir
def deps do
  [
    {:kotoba, "~> 0.1"}
  ]
end
```

Then run `mix deps.get`.

## 2. Run the installer

```sh
mix kotoba.install --dry-run   # shows the changes as a diff
mix kotoba.install
```

The installer changes three files, and prints what it changed:

* `assets/js/app.js`: it adds `import { Kotoba } from "kotoba"` and puts
  `Kotoba` in the `hooks` of the `LiveSocket`.
* `assets/css/app.css`: it adds the Kotoba style sheet, and the Sumi theme
  import as a comment.
* `config/config.exs`: it adds `config :kotoba, storage: Kotoba.Storage.Local`.

It does not add what a file already has, so you can run it again. When it
cannot edit a file safely, it changes nothing in that file and prints the
lines to add. See "The limits of the installer" below.

## 2b. Or make the changes by hand

To make the installer's changes by hand:

```js
// assets/js/app.js
import { Kotoba } from "kotoba"

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Kotoba},
})
```

Put the CSS lines below the other `@import` lines of `app.css` (the
installer puts them there):

```css
/* assets/css/app.css */
@import "../../deps/kotoba/priv/static/kotoba.css";
/* The Sumi theme, when you want it: */
/* @import "../../deps/kotoba/priv/static/kotoba-sumi.css"; */
```

```elixir
# config/config.exs
config :kotoba, storage: Kotoba.Storage.Local
```

### The limits of the installer

The installer reads `assets/js/app.js` with a small scanner, not with a
JavaScript parser. The scanner skips strings and comments. It does not see
these cases correctly:

* A regular expression literal that has a bracket or a quote in it,
  before the `new LiveSocket(...)` call.
* `hooks` given as a shorthand property (`{hooks}`) or as a quoted key
  (`"hooks": ...`).
* `hooks` given as a computed value, for example a function call.

In these cases the installer does not write to the file. It prints the
import and the hook line, and you add them by hand as shown above.

## 3. Let esbuild find `kotoba` in `deps/`

The import `from "kotoba"` resolves through `NODE_PATH`. The Phoenix
generators already give the esbuild profile a `NODE_PATH` with `deps/`.
If your profile has no `NODE_PATH`, add it in `config/config.exs`:

```elixir
config :esbuild,
  my_app: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]
```

The installer prints this note when the profile has no `NODE_PATH`.

### A path dependency

Mix does not copy a path dependency (`{:kotoba, path: "../kotoba"}`) into
`deps/`. The installer then points the `@import` lines of `app.css` at the
dependency's directory (for example `../../../kotoba/priv/static/kotoba.css`),
and prints the `NODE_PATH` entry that esbuild needs: the directory that
holds the dependency, relative to `config/`:

```elixir
env: %{
  "NODE_PATH" => [
    Path.expand("../deps", __DIR__),
    Path.expand("../..", __DIR__),
    Mix.Project.build_path()
  ]
}
```

A checkout of Kotoba has no built bundle until `mix kotoba.build` runs in
it, so run that task in the Kotoba directory before the app's
`mix assets.build`.

## 4. Give the uploads a directory

The local storage adapter needs a configured root directory. For
production, give an absolute path outside the release, in the `:prod`
block of `config/runtime.exs`:

```elixir
# config/runtime.exs
if config_env() == :prod do
  config :kotoba, Kotoba.Storage.Local,
    root: System.get_env("KOTOBA_UPLOADS", "/var/lib/my_app/uploads"),
    url_prefix: "/uploads/kotoba"
end
```

For development, in `config/dev.exs`:

```elixir
# config/dev.exs
config :kotoba, Kotoba.Storage.Local, root: Path.expand("../tmp/uploads", __DIR__)
```

`config/runtime.exs` runs in every environment, after `config/dev.exs`.
Outside the `:prod` block, its root would also replace the development
root, and uploads in development would fail.

Serve the files with `Kotoba.Storage.Local.Plug`, in the endpoint before
the router:

```elixir
plug Kotoba.Storage.Local.Plug
```

Uploads are optional. The [Uploads](uploads.md) guide has the full setup.

## 5. Add the field to a schema

`Kotoba.Content` is an Ecto type over a `:map` column (`jsonb` in
PostgreSQL):

```elixir
# The migration
alter table(:posts) do
  add :body, :map
end
```

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
    |> validate_required([:title])
  end
end
```

An empty editor posts an empty document, not `nil`, so
`validate_required/2` does not catch it. See `validate_body/1` in the
[Forms](forms.md) guide.

The stored value has the document, its HTML and its plain text. Kotoba
renders the HTML and the text when it casts the value, so every row has a
fresh cache.

## 6. Put the editor in a LiveView form

Import the components, for example in the `html_helpers` of your web
module:

```elixir
import Kotoba.Components
```

Then, in the LiveView:

```heex
<.form for={@form} id="post-form" phx-change="validate" phx-submit="save">
  <.input field={@form[:title]} label="Title" />
  <label id="post-body-label">Body</label>
  <.kotoba field={@form[:body]} id="post-body" label_id="post-body-label" />
  <.button>Save</.button>
</.form>
```

The editor posts the document with the form, so the form's own
`phx-change` and `phx-submit` events have it. The LiveView needs no other
event for the editor. The [Forms](forms.md) guide explains the form data,
and the `change` attribute for a LiveView that wants each change as an
event.

The editor is a LiveView hook, so it works only in a LiveView (or a
LiveComponent), not on a page that a controller renders.

## 7. Show the stored content

```heex
<.kotoba_content content={@post.body} />
```

`Kotoba.Components.kotoba_content/1` shows the cached HTML. The HTML is
safe: Kotoba escapes every string and never passes raw HTML through. See
the [Security](security.md) guide.

## Next

* [Forms and changesets](forms.md)
* [Uploads](uploads.md)
* [Prompts and mentions](prompts.md)
* [Custom nodes](custom_nodes.md)
* [Theming](theming.md)
