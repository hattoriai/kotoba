# Security

A document comes from the browser, so Kotoba treats every document as
input from the person who wrote it. This guide tells what Kotoba does, and
what your app must do.

## No raw HTML

Kotoba never passes raw HTML through. There is no HTML node, and a
document is a tree of known nodes with typed attributes.

* `Kotoba.Document.parse/2` checks the document envelope and each node.
  A node of a type that the registry does not know is kept as a
  `Kotoba.Nodes.Unknown` node. It renders as an empty, inert
  `span.kotoba-unknown`.
* `Kotoba.Renderer` renders through `Phoenix.HTML`, so it escapes every
  string. A node module that returns a plain string from `render_html/2`
  gets it escaped too.
* `Kotoba.Sanitizer` checks each node before it renders: its attributes
  (their types, no control characters, length limits), its place in the
  tree (a list holds only list items, a link holds no other link, and so
  on) and its URLs. A node that fails a check renders as an unknown node.
  The renderer does not raise.

## Links

A link renders as an anchor only when its URL is relative or has an
allowed scheme. The default schemes are `http`, `https` and `mailto`:

```elixir
config :kotoba, allowed_link_schemes: ~w(http https mailto tel)
```

A link with a URL that is not safe (`javascript:`, `data:`, …) renders as
its text. Anchors have `rel="noopener nofollow"`. The editor gets the same
list of schemes, so it refuses the same URLs.

## Policies

Render content from people that the app does not trust with the
`:untrusted` policy:

```heex
<.kotoba_content content={@comment.body} policy={:untrusted} />
```

With `:untrusted`, links render as their text, with no anchor, and
attachments render as their file name, with no image and no link. See
`Kotoba.Sanitizer`.

## The cached HTML

`Kotoba.Content` keeps the rendered HTML of the document (with the
`:default` policy) in the row. `Kotoba.Content.cast/1` always renders it
again from the document: it never takes HTML from its input, not even
from a `Kotoba.Content` struct. So the HTML
in a row that Kotoba wrote is safe.

`Kotoba.Components.kotoba_content/1` trusts the `html` of a stored row,
and shows it with no new rendering. So:

* A row that code outside Kotoba writes (a SQL script, an import, another
  service) must go through `Kotoba.Content.cast/1` or
  `Kotoba.Content.rerender/2` first.
* Or render it with `policy={:untrusted}`, or with `nodes`: then the
  component renders the document again and does not use the cache.

## Uploads

Kotoba reads the first bytes of each uploaded file on the server and
keeps a content type only when the bytes prove it: PNG, JPEG, GIF, WebP,
PDF, UTF-8 plain text, ZIP and Office files. Every other file is
`application/octet-stream`. The type that the browser sends is not used.
The storage key takes its extension from the checked type, so a key never
ends in `.html` or `.svg`. The file name is cleaned of control and
bidirectional format characters, and is only shown as text.

An uploaded file is content from a person. Serve it so that it cannot run
a script on your origin:

* `X-Content-Type-Options: nosniff`.
* The checked content type, never the type that the browser sent.
* `Content-Disposition: attachment` for every type that is not an image
  or a PDF (`Kotoba.Attachments.inline?/1`).
* `Content-Security-Policy: default-src 'none'; sandbox`.

`Kotoba.Storage.Local.Plug` sends all of these headers, and
`Cache-Control: private`. Do not serve the upload directory with
`Plug.Static`: it takes the type from the extension and sends none of
these headers.

An adapter for S3 or another store must set the content type from
`meta.content_type` and `Content-Disposition: attachment` for each type
that `Kotoba.Attachments.inline?/1` refuses. Without the disposition, the
store serves an uploaded HTML file inline, as a page on the store's
origin. The `Kotoba.Storage` docs have an example.

Serve private files through a path in your app that checks access (for
example a controller that redirects to a short-lived signed URL). The URL
of a file is in the stored document, and every reader of the document
sees it.

## What your app must do

* **Authorize every event.** The editor's events (`kotoba:change`,
  `kotoba:prompt`, the upload events) and the form events come from the
  browser. Check in each `handle_event/3` that the person can edit the
  record.
* **Check the features.** An editor's `features` limit what the person can
  make in the browser, not what a request can post. Check them in the
  changeset with `Kotoba.Content.validate_features/3` (see the
  [Editing features](features.md) guide).
* **Scope the prompts.** A prompt callback runs with the query from the
  browser. Search only the things that the person can see, for example
  with an arity-2 callback that reads the scope from the socket. The
  `items` of a local prompt are in the page, so give only the ones that
  the person can see.
* **Check mentions and app nodes.** The `id` of a mention and the
  attributes of an app node (a prompt's `attrs` too) come from the browser. Check them before you
  act on them (a notification, a link to a record).
* **Read-only is not access control.** `readonly` changes the editor in
  the browser only. Check on the server that the person can save.
* **Limit the size.** A document has no size limit in Kotoba. Limit the
  size of the form params in your endpoint (`Plug.Parsers` `:length`)
  and of the WebSocket messages, in the endpoint:
  `socket "/live", Phoenix.LiveView.Socket, websocket: [max_frame_size: 1_000_000, connect_info: [session: @session_options]]`.
