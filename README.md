# Kotoba

Kotoba (言葉, "words") is rich text for Phoenix. It gives your app:

* a rich-text editor for LiveView forms, built on
  [Lexical](https://lexical.dev): text formats, headings, quotes, lists and
  check lists, links, highlighted code blocks, tables, file attachments,
  mentions, and your own nodes;
* `Kotoba.Content`, an Ecto type that stores the document with a cached
  HTML and text rendering;
* safe rendering to HTML, text and Markdown, with no raw HTML anywhere.

The editor is a prebuilt JavaScript bundle in the Hex package. Your app
does not run Node.js for it: you add the hook and one style sheet.

## Install

Kotoba needs Elixir 1.18 or later (it uses the built-in `JSON` module),
Phoenix 1.8 and Phoenix LiveView 1.2. CI runs the tests on Elixir 1.18
(OTP 27) in a separate `floor` job, as well as on the current version.

Add `kotoba` to the deps in `mix.exs`:

```elixir
def deps do
  [
    {:kotoba, "~> 0.1"}
  ]
end
```

Then run:

```sh
mix deps.get
mix kotoba.install
```

The installer adds the hook to `assets/js/app.js`, the style sheet to
`assets/css/app.css` and the storage adapter to `config/config.exs`, and
prints what it changed. Give `--dry-run` to see the changes first. It does
not add what a file already has, so you can run it again.

### The manual steps

To make the same changes by hand, import the hook in `assets/js/app.js`
and add it to the hooks of the `LiveSocket`:

```js
import { Kotoba } from "kotoba"

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Kotoba},
})
```

Import the style sheet in `assets/css/app.css` (and the Sumi theme, if you
want it: Sumi is the design system of Hattori AI, the makers of Kotoba). Put these lines below the other `@import` lines of `app.css`
(the installer puts them there):

```css
@import "../../deps/kotoba/priv/static/kotoba.css";
/* @import "../../deps/kotoba/priv/static/kotoba-sumi.css"; */
```

Name the storage adapter for uploads in `config/config.exs`:

```elixir
config :kotoba, storage: Kotoba.Storage.Local
```

### `NODE_PATH=deps`

`import { Kotoba } from "kotoba"` resolves through the `NODE_PATH` of your
esbuild profile, which must have `deps/`. The Phoenix generators already
set it. If your profile has no `NODE_PATH`, add it in `config/config.exs`:

```elixir
env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
```

## Use

```elixir
schema "posts" do
  field :body, Kotoba.Content
end
```

```heex
<.form for={@form} phx-change="validate" phx-submit="save">
  <label id="post-body-label">Body</label>
  <.kotoba field={@form[:body]} id="post-body" label_id="post-body-label" />
</.form>

<.kotoba_content content={@post.body} />
```

Import the components in the `html_helpers` of your web module:

```elixir
import Kotoba.Components
```

The editor posts the document with the form, as a JSON string that
`Kotoba.Content` casts, so the form's own `phx-change` and `phx-submit`
events have it. `<.kotoba_content>` shows the stored content as safe
HTML.

## Guides

* [Quickstart](guides/quickstart.md): install, the schema, the form and
  the rendered content.
* [Forms and changesets](guides/forms.md): what the form posts, the
  changeset, the LiveView events and the server pushes.
* [Uploads](guides/uploads.md): LiveView uploads, the storage adapters and
  how to serve the files.
* [Prompts and mentions](guides/prompts.md): `@` menus with results from
  the LiveView.
* [Custom nodes](guides/custom_nodes.md): your own nodes, with
  `mix kotoba.gen.node`.
* [Theming](guides/theming.md): the `--kotoba-*` properties and the Sumi
  theme.
* [Security](guides/security.md): what Kotoba checks, and what your app
  must do.
* [Accessibility](guides/accessibility.md): the roles and the keyboard.
* [Known limits](guides/limits.md).

## Development

The editor source is TypeScript in `assets/`. The built files in
`priv/static` are not in the repository; the Hex package has them.

```sh
mix deps.get
mix kotoba.build    # npm ci in assets/ when necessary, then esbuild
mix dev             # the development server on http://localhost:4099
```

`mix kotoba.build` runs in the `:dev` environment and needs `npm`. It
empties `priv/static` and writes the four files of the package:
`kotoba.esm.js`, `kotoba.cjs.js`, `kotoba.css` and `kotoba-sumi.css`.

`mix dev` runs `dev.exs`: a Phoenix endpoint with the editor in a form,
the `@` prompt, uploads to `tmp/uploads`, an app node made with
`mix kotoba.gen.node` (in `dev/`), buttons that send each server event,
and the Sumi theme at `/?theme=sumi`. Set `PORT` for another port. esbuild
watchers rebuild the bundle and the node modules, and the page reloads.
Restart `mix dev` after a change in `dev/lib`.

### Tests

```sh
mix test                   # the ExUnit suite
mix test --include build   # also mix kotoba.build and mix hex.build
mix test.e2e               # the Playwright browser tests
mix precommit              # compile, format, credo --strict and test
mix dialyzer
```

The browser tests in `e2e/` use Playwright with Chromium. Install the
browser once:

```sh
cd e2e && npm ci && npx playwright install chromium
```

`mix test.e2e` runs `npm ci` in `e2e/` when `e2e/node_modules` is missing,
builds the bundle, and starts its own development server, without
watchers, on port 4098 (set `E2E_PORT` for another port). A `mix dev` on
port 4099 can keep running.

### Release

`mix release` (in this repository, an alias that replaces Mix's `release`
task) builds the bundle, checks that `priv/static` holds only the
four bundle files (`mix kotoba.release_check`), publishes to Hex, and tags
and pushes `v<version>`.

## License

Kotoba is released under the Apache License, Version 2.0. See `LICENSE`.

The built editor includes third-party code under the MIT licence:
[Lexical](https://lexical.dev) (Meta Platforms, Inc. and affiliates),
[PrismJS](https://prismjs.com) (Lea Verou) and
[`@preact/signals-core`](https://github.com/preactjs/signals) (the Preact
team). The toolbar icons are from [Lucide](https://lucide.dev) (ISC
licence); some of them come from Feather (MIT licence). See `NOTICE` for
the full notices.
