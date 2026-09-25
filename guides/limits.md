# Known limits

These are the known limits of Kotoba 0.1.

## Prompt queries have no spaces

A prompt query ends at white space, so a space closes the menu. A query
can find "Ada", but not "Ada Lovelace". A query has at most 64
characters. See the [Prompts](prompts.md) guide.

## The cache does not see a change of the registry or of the link schemes

`Kotoba.Content` keeps the rendered HTML and text in the row, with a cache
version. `Kotoba.Components.kotoba_content/1` renders the document again
only when the cache version of Kotoba changes. It does not see a change
of your node registry (`config :kotoba, nodes:`) or of
`config :kotoba, allowed_link_schemes:`. After such a change, stored rows
keep their old HTML until you render them again:

```elixir
import Ecto.Query

Repo.transaction(fn ->
  from(p in Post, where: not is_nil(p.body))
  |> Repo.stream()
  |> Enum.each(fn post ->
    post
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.force_change(:body, Kotoba.Content.rerender(post.body))
    |> Repo.update!()
  end)
end, timeout: :infinity)
```

`Kotoba.Content` compares two values by their documents only, so
`Ecto.Changeset.change/2` sees no change in a new cache.
`Ecto.Changeset.force_change/3` writes it.

A node that is only in the `nodes` attribute of the component, and not in
the config, is cached as an unknown node. See the
[Custom nodes](custom_nodes.md) guide.

## Direct uploads to a cloud store are not supported

LiveView's `external:` uploads are not supported. Each file comes to the
LiveView, Kotoba checks its bytes, and the storage adapter then sends it
to the store. See the [Uploads](uploads.md) guide.

## Two short selection races of Lexical

Lexical reads a selection change from the browser a moment late. The
toolbar and the link form read the selection of the page, so they act on
the text that the person sees. Two cases are still open. Both need keys
less than one frame apart, which a person does not type:

* Shift+Tab within about 2 ms of a click or of Shift+Arrow can put the
  focus back in the editor. The content does not change.
* Backspace or Delete at once after an arrow key can use the old
  selection. This is the behaviour of every Lexical editor.

## Bundle size

The editor bundle is about 425 KB, 140 KB with gzip. It has Lexical, its
plugins and the Prism grammars of `@lexical/code-prism` (more languages
than the toolbar offers, so a pasted code block in another language keeps
its highlighting). The bundle is part of your `app.js`, so every page that
loads `app.js` pays for its size.

## `window.Prism`

The editor has its own copy of Prism. It saves the page's `window.Prism`
before it loads its copy and puts it back after, so a page's Prism keeps
working. A page cannot use the editor's Prism through `window.Prism`, and
a Prism plugin on the page does not change the editor's highlighting.

## The hidden input after a patch uses `phx:update`

After a LiveView patch, the hook writes the current document into the
hidden input again. It uses LiveView's `phx:update` event, which is not in
the documented hook API. The form events do not depend on it (they read
the form through `formdata`). See the [Forms](forms.md) guide.

## The installer reads `app.js` with a scanner

`mix kotoba.install` does not parse JavaScript. For some forms of
`app.js` it cannot make the edit, and it prints the lines to add by hand.
See the [Quickstart](quickstart.md#the-limits-of-the-installer).

## Lexical is pinned

The bundle has Lexical 0.51, and the document envelope records
`"lexical" => "0.51"`. A later Kotoba version moves to a new Lexical
version with its own changes to the documents, if they are necessary.
