# Embeds

An embed is something live of your app's in a document: a canvas, a
grid, a chart, a poll. The document keeps what your app needs to find it
(a `kind` and a `ref`, and a `title`), and your LiveView renders it, in
the editor, as it renders anything else. People use it in place, take it
full screen, and write around it.

Kotoba knows nothing of what an embed is. A canvas is
[Hakushi](https://github.com/hattoriai/hakushi)'s, a grid
[Masu](https://github.com/hattoriai/masu)'s; your app depends on the
library of what it embeds, and Kotoba on neither.

## Turn them on for an editor

Embeds are the `embeds` feature (on by default, see
[Editing features](features.md)), and an editor has them when your app
says so:

```heex
<.form for={@form} id="post-form" phx-change="validate">
  <.kotoba field={@form[:body]} id="post-body" embeds />
</.form>

<.kotoba_embeds for="post-body" label="Canvas" icon="canvas">
  <:embed :let={embed}>
    <.diagram id={"diagram-" <> embed.id} ref={embed.ref} full={embed.full} on_full={embed.toggle_full} />
  </:embed>
  <:picker>
    <.kotoba_embed_option :for={d <- @diagrams} phx-click="insert_diagram" phx-value-id={d.id} title={d.title} />
  </:picker>
</.kotoba_embeds>
```

`kotoba_embeds/1` goes outside the editor's form, once for each editor
with embeds. An editor without `embeds` has no embeds: no button, and an
embed in its document shows as its title.

Each editor chooses what it embeds: its `:embed` slot renders the kinds
it knows (by `embed.kind`), and its picker offers what it lets people
insert. Two editors of one page can embed different things.

### The `:embed` slot

The slot renders one embed. `:let` gets a map:

| Key | |
| --- | --- |
| `id` | the id of the embed's slot, unique in the page: use it in the ids of what you render (a canvas's `"diagram-" <> embed.id`), as the same thing can be in a document twice |
| `kind`, `ref`, `title` | the embed's, as the document has them |
| `editor` | the editor's id |
| `full` | whether the embed is full screen now |
| `toggle_full` | a `Phoenix.LiveView.JS` command that takes it full screen and back, for a button |
| `readonly` | the `readonly` of `kotoba_embeds/1` |

What you render is your LiveView's own: its events go to your LiveView,
a LiveComponent in it (a canvas, a grid) is a LiveComponent as any, and a
change of your assigns updates it. LiveView puts it in the embed's place
in the document with a portal (`<.portal>`): the same element stays there
as people type around it, and goes, as it is, into a layer over the page
when it goes full screen, and back.

An embed takes the height of `--kotoba-embed-height` (24rem); give what
you render `height: 100%`, or set the property on `.kotoba-embed-slot`.
An embed carries its kind (`data-kind`), so each kind may have its own:
a grid that takes the height of its rows, a canvas a fixed height.

```css
.kotoba-embed[data-kind="grid"] .kotoba-embed-slot { height: auto; }
```

### Insert an embed

With a `:picker`, the toolbar has a button that opens it: its words are
`label` ("Canvas") and its icon `icon` (`embed`, `canvas`, `grid` or
`chart`). The picker shows your options: `kotoba_embed_option/1` is a
button with an icon, a title and a line about it, and `<h3>` headings
divide them. An option's event inserts the embed, with
`Kotoba.Live.insert_embed/4`, which puts it at the person's selection
and closes the picker:

```elixir
def handle_event("insert_diagram", %{"id" => id}, socket) do
  diagram = Diagrams.get!(id)
  {:noreply, Kotoba.Live.insert_embed(socket, "post-body", "canvas", diagram.id, title: diagram.title)}
end

def handle_event("new_diagram", %{"kit" => kit}, socket) do
  {:ok, diagram} = Diagrams.create(%{kit: kit, title: "Untitled"})
  {:noreply, Kotoba.Live.insert_embed(socket, "post-body", "canvas", diagram.id, title: diagram.title)}
end
```

`:let` on `:picker` gets `close`, a JS command that closes it, for a
Cancel of your own. Escape and a click outside close it too.

### A link that becomes the embed

People share links: a link to a canvas of your app, pasted or dropped in
the editor, can become the canvas itself. Give `kotoba_embeds/1` a
`resolve` function of the URL:

```elixir
def resolve(url) do
  with %URI{host: "app.example.com", path: path} <- URI.parse(url),
       {:ok, %{route: "/diagrams/:id", path_params: %{"id" => id}}} <- route(path),
       %Diagram{} = diagram <- Diagrams.get_for(current_user(), id) do
    %{kind: "canvas", ref: diagram.id, title: diagram.title}
  else
    _other -> nil
  end
end

defp route(path) do
  case Phoenix.Router.route_info(MyAppWeb.Router, "GET", path, "app.example.com") do
    :error -> :error
    info -> {:ok, info}
  end
end
```

```heex
<.kotoba_embeds for="post-body" resolve={&resolve/1}>
```

* A URL pasted alone on an empty line goes in as a link at once, and
  becomes the embed when the server answers. A person who goes on
  typing on that line keeps the link, and so does a URL pasted in a
  sentence.
* A URL dropped on the editor (dragged from another tab) goes in after
  the block it lands on: the embed, or a link.
* `resolve` returns `nil` for a URL that is not yours, or not this
  person's to see: it stays a link. Check the person's access in it, as
  for any of your pages.
* A read-only editor resolves nothing. Undo turns the embed back into the
  link.

### In the document

* Keys in an embed are the embed's: Delete in a canvas deletes its node,
  not the embed.
* A click on an embed's edge selects it, and Backspace or Delete deletes
  it. Backspace at the start of the block after an embed (or Delete at
  the end of the block before one) deletes it too, as it deletes a
  horizontal rule. Undo brings it back, live.
* The embed's text is its `title`, in the text and the Markdown of the
  document, unless your app renders it (below).

## A page that reads the document

A read-only editor with `show_toolbar={false}` is the document as a
page, with its embeds live in it:

```heex
<.kotoba field={@form[:body]} id="post-body" embeds readonly show_toolbar={false} />
<.kotoba_embeds for="post-body" readonly>
  <:embed :let={embed}><.diagram ref={embed.ref} readonly={embed.readonly} ... /></:embed>
</.kotoba_embeds>
```

`readonly` reaches your slot as `embed.readonly`, for content that reads
and does not write (a canvas people pan and zoom, and do not change). A
read-only editor opens no picker.

`kotoba_content/1` renders stored content as HTML, with no LiveView: an
embed there is what your app renders it as (below), by default a
`div.kotoba-embed` with its kind, ref and title.

## Render an embed as Markdown, HTML and text

Kotoba does not know what an embed is, so your app says what it renders
as. Give the renderers a function of the embed and the format:

```elixir
defmodule MyApp.Embeds do
  # A canvas as its Mermaid diagram, which Markdown viewers draw.
  def render(%{kind: "canvas", ref: id}, :markdown) do
    diagram = Diagrams.get!(id)
    Hakushi.Kit.to_markdown(diagram.kits, diagram.graph)
  end

  # In HTML, its picture (Renderer.tag/3 escapes the attributes).
  def render(%{kind: "canvas", ref: id, title: title}, :html),
    do: Kotoba.Renderer.tag("img", [src: Diagrams.image_url(id), alt: title], :void)

  def render(_embed, _format), do: nil
end
```

```elixir
Kotoba.Renderer.to_markdown(doc, embed: &MyApp.Embeds.render/2)
```

```heex
<.kotoba_content content={@post.body} embed={&MyApp.Embeds.render/2} />
```

Or for every render, the HTML that `Kotoba.Content` caches when it casts
a document included:

```elixir
config :kotoba, embed: &MyApp.Embeds.render/2
```

The function returns safe HTML for `:html` (a string is escaped, as for
any node), Markdown or text for `:markdown` and `:text`, or `nil` for the
default.

## Read an embed back from Markdown

In Markdown, an embed is what your app renders (or its title) between
two comments that say what it is, which Markdown viewers leave out:

```markdown
<!-- kotoba:embed {"kind":"grid","ref":"7","title":"Open tasks"} -->

| Task | Due |
| --- | --- |
| Write the guide | 2026-11-02 |

<!-- /kotoba:embed -->
```

`Kotoba.Content.from_markdown/2` reads it back as the embed, of any kind,
with no code of yours: a document exported and imported again has its
embeds. Your app's reader, if you give one, gets it first, as
`%{embed: %{kind, ref, title}, language, code}` (the language and code of
the first fenced block in it, a canvas's diagram), and returns:

* `nil`, for the embed as it was;
* another embed, for one of your own (the canvas made anew from its
  diagram, when the ref is not one of this app's, or not this person's);
* `false`, for its content as Markdown (the table, the diagram).

A ref read from Markdown is the person's input, as a document's is:
your `:embed` slot checks that they may see what it names.

Markdown from elsewhere has no comments. `Kotoba.Content.from_markdown/2`
reads a fenced block of it as an embed when your app's reader returns
one:

```elixir
def read(%{language: "mermaid", code: code}) do
  case Hakushi.Kit.from_markdown(@kits, code) do
    {:ok, graph, kit} ->
      {:ok, diagram} = Diagrams.create(%{graph: graph, kits: [kit], title: "Imported"})
      %{kind: "canvas", ref: diagram.id, title: diagram.title}

    :error ->
      nil
  end
end

def read(_block), do: nil
```

```elixir
Kotoba.Content.from_markdown(markdown, embed: &MyApp.Embeds.read/1)
```

With `config :kotoba, embed_from_markdown: &MyApp.Embeds.read/1`, every
import reads embeds, and so does Markdown pasted in the editor. A block
your reader returns `nil` for stays a code block. Only a block of the
document's root becomes an embed (not one in a list or a quote).

## Collaboration

In a shared document (see [Collaboration](collaboration.md)), an embed
someone inserts reaches everyone's editor, and each person's LiveView
renders it for them. What is in it is your app's: a Hakushi canvas with
`live` is shared on its own, in its own room, and its people are that
room's wherever they are. Someone reading the document sees the cursor of
someone on the canvas's own page, and the other way round.

* Give the canvas the same user as the editor (`Kotoba.Collab.token/3`'s
  `user`): the person is one person in both rooms.
* Issho's pointers of the document's room (`Issho.Components.pointers/1`)
  leave the canvas to its room, which draws its people there; following
  someone who goes into the canvas follows them on it too.
* A pointer over an embed is no caret of the text.
* An embed deleted from the document lets the canvas's room go (Hakushi
  releases it); full screen keeps the canvas in its room.
* A reader of the document (`readonly`) is a viewer of the canvas's room.

See Hakushi's [In a page](https://hexdocs.pm/hakushi/embedding.html) guide.

## Test an embed

The editor tells the embeds component when a slot comes, with
`"kotoba:embeds"`; send it in a test as the browser does:

```elixir
view
|> with_target("#post-body-embeds")
|> render_hook("kotoba:embeds", %{"action" => "mount", "slot" => "post-body-embed-3", "kind" => "canvas", "ref" => "7"})

assert view |> element("#post-body-embeds-portal-post-body-embed-3") |> render() =~ "diagram-post-body-embed-3"
```

The content of a portal is in a `<template>`, which LiveViewTest does not
query: render the portal and match its HTML.

## Style

| Property | Default | |
| --- | --- | --- |
| `--kotoba-embed-height` | `24rem` | the height of an embed in the document |
| `--kotoba-embed-radius` | the radius and a little more | the corners of an embed |
| `--kotoba-embed-layer` | `60` | the `z-index` of the full screen layer and the picker |

The classes are `.kotoba-embed` (the block), `.kotoba-embed-slot` (where
your content goes; none of the editor's text styles reach it),
`.kotoba-embed-full` and `.kotoba-embed-full-body` (full screen),
`.kotoba-embed-picker` and `.kotoba-embed-option`.
