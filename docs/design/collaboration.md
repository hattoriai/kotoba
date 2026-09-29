# Design: real-time collaboration

Status: proposed, for #27. This document answers the design questions of
the issue before the implementation PRs. It becomes the Collaboration guide
when the feature lands.

## Summary

Several people edit one document at once. The editor binds Lexical to a
[Yjs](https://yjs.dev) document with `@lexical/yjs`. A Phoenix Channel
carries the Yjs sync and awareness messages. A `y_ex` `Yex.DocServer`
process per document merges them on the server and stores the Yjs state.
The browsers send a Lexical JSON snapshot of the document, which the server
checks with `Kotoba.Content` and stores as the field's value. So the stored,
rendered and checked document stays `Kotoba.Content`, as today.

```
browser A ─┐                       ┌─ Kotoba.Collab.DocServer (y_ex, one per document)
browser B ─┼─ Phoenix Channel ─────┤    merges updates, awareness, stores Yjs state
browser C ─┘  (binary Yjs          └─ the app's store: Yjs state + Kotoba.Content snapshot
               messages)
```

## What exists, and what we checked

* **`@lexical/yjs` 0.51**, the version of our other Lexical packages. It
  has a binding with no React (`createBinding`, `syncLexicalUpdateToYjs`,
  `syncYjsChangesToLexical`, `createUndoManager`, `syncCursorPositions`);
  React's `CollaborationPlugin` is a thin layer over it. We checked it
  with two headless editors and two Yjs documents: they converge after
  concurrent typing in one paragraph, concurrent list items and a format
  change, **when the network delivers updates asynchronously**. A relay
  that applies an update inside the other editor's update listener loses
  edits: the transport must never apply a remote update synchronously
  inside a Lexical update (a WebSocket never does).
* **`y_ex` 0.12** (Hex, Rust `yrs` binding, about 150k downloads, released
  in September 2026). `Yex.DocServer` is a GenServer that speaks the
  y-protocols sync and awareness messages (`process_message_v1/3`), with
  callbacks for updates and awareness changes.
* **`y-phoenix-channel` 0.3** (npm, same author): a Yjs provider over a
  Phoenix Channel, with binary messages, resync after a server restart,
  and a Phoenix demo with Ecto persistence and `Phoenix.Presence`.
* **Size**: `yjs`, `@lexical/yjs`, `y-protocols` and `y-phoenix-channel`
  add about 163 KB minified, 52 KB with gzip (our bundle is 579 KB and
  188 KB). Most apps will not collaborate, so this goes in a separate
  bundle (see "The client").

`@lexical/yjs` stores each node as its **internal properties** (`__type`,
`__format`, `__attachment`, …): an element is an `XmlText` with them as
attributes, a text node a `Map` followed by its text, a decorator an
`XmlElement`. This is not the JSON of `exportJSON`, and an app node's
properties are its own. So the server does **not** turn Yjs into Lexical
JSON: the browsers do, with the real node classes (see "Storage").

## The client

* A second prebuilt file, `priv/static/kotoba-collab.esm.js`, with `yjs`,
  `@lexical/yjs`, `y-protocols` and the provider. The page loads it only
  where it collaborates. It must use the editor's own copy of Lexical: a
  second copy of `lexical` breaks node classes and `$` functions. The
  build aliases `lexical` (and the `@lexical/*` packages that
  `@lexical/yjs` imports) to a small module that reads the editor's copies
  at run time, as extension modules already get them (`ExtensionAPI`).
* The component: `<.kotoba field={@form[:body]} collab={@collab} />`, where
  `@collab` comes from `Kotoba.Collab.token/3` (below). The hook then:
  * creates the Yjs document, the provider (the Channel), and the binding;
  * syncs Lexical updates to Yjs (every update but `skip-collab` ones) and
    Yjs events to Lexical;
  * replaces `@lexical/history` with the Yjs `UndoManager`: **undo is per
    person**, it undoes only one's own changes;
  * shows the other people's carets and selections (`syncCursorPositions`,
    a cursors layer in the surface);
  * sends the JSON snapshot (see "Storage") instead of writing the hidden
    input on every change.
* An editor with no `collab` works as today, with none of this code.

## The transport and the document process

* A Channel module in the app: `use Kotoba.Collab.Channel` on the app's
  socket, topic `"kotoba:" <> document_id`. Binary frames
  (`{:binary, data}`) carry the y-protocols messages, as in the
  `y-phoenix-channel` demo. The LiveView socket is not used: it has no
  binary events, and a document outlives a LiveView.
* `Kotoba.Collab.DocServer` (`use Yex.DocServer`): one per document,
  started on the first join, registered in the cluster (`:global` by
  default, a registry option for apps with Horde or `:syn`), stopped a
  while after the last person leaves (a TTL, default 30 s), under a
  `DynamicSupervisor` that the app starts.
* Updates are broadcast with `Endpoint.broadcast_from/4`, so they reach
  every node through `Phoenix.PubSub`.
* **Recovery instead of hand-off.** When the node of a document dies, its
  people rejoin, a new process starts on another node from the store,
  and each browser sends what the store lacks (the sync protocol compares
  state vectors). A CRDT loses nothing in this, so there is no process
  hand-off to build.

## Storage

The app gives a store module (`@behaviour Kotoba.Collab.Store`):

```elixir
@callback load(document_id) :: {:ok, %{state: binary() | nil, content: Kotoba.Content.t() | nil}} | {:error, term}
@callback save_state(document_id, state :: binary()) :: :ok | {:error, term}
@callback save_content(document_id, Kotoba.Content.t(), meta :: map()) :: :ok | {:error, term}
```

and the guide has an Ecto example: a `body_yjs` binary column next to the
`body` (`Kotoba.Content`) column.

* **The Yjs state** (`Yex.encode_state_as_update/1`, compacted) is saved
  debounced (2 s after the last update), when the last person leaves, and
  when the process stops. It is the editing state, not what is rendered.
* **The snapshot** is the Lexical JSON document. A browser that made a
  change sends it, debounced (the same `debounce` as `kotoba:change`), with
  the Yjs state vector it was made from. The server takes the snapshot of
  the newest state, checks it (`Kotoba.Content.cast/1`, then the app's
  check, by default `validate_features/3` with the editor's features) and
  saves it with `save_content/3`. The rendered page reads it, as today.
* **Opening a document with no Yjs state** (an existing document, or a
  document stored before collaboration): the server loads its content and
  gives the first person to join the role of **bootstrapper** in the join
  reply. That browser loads the JSON into the editor, and the binding
  writes it to Yjs; the others wait for the first sync. Two browsers that
  both bootstrapped would duplicate the document, so the server gives the
  role once, and again only if that person leaves before the first update.

## Authorization

* The LiveView makes a signed, short-lived token for the person and the
  document: `Kotoba.Collab.token(socket, document_id, role: :write | :read,
  user: %{id:, name:, color:})` (a `Phoenix.Token`, 5 minutes to join).
  The Channel's `join/3` verifies it, and calls the app's `authorize/3`
  callback again, as a controller should not trust a token alone.
* **Read-only people** can join and follow the document live: the channel
  answers their sync requests (step 1) and relays awareness, and drops
  their updates (sync step 2 and update messages).
* Each message has a size limit (default 1 MB), and the channel closes on
  a message that is not valid y-protocols.

## Checking the content

Updates arrive as a stream of Yjs operations. The server cannot check
features or the sanitizer on them without the node classes. So:

* The **editor** keeps its features, as today: a pasted table in an editor
  without tables comes in as paragraphs, before it becomes a Yjs update.
* The **snapshot** is checked on the server before it is saved, like a form
  post. A snapshot that fails is not saved; the last valid one stays, the
  server logs it, and the editor that sent it is told
  (`kotoba:collab_error`).
* The **Yjs state** can still hold what the snapshot refused, if a person
  sends crafted updates. It is only shown in editors, which run the same
  node classes and feature checks as today (an unknown node shows as a
  placeholder, a link with a bad scheme as text), and it is never
  rendered as a page. A person who can send updates could type that
  content anyway; the guide says so plainly.

## Forms and saving

A collaborative field has no "unsaved changes": the document is saved as
people type. In a LiveView form:

* the hidden input still holds the current document, so a form with other
  fields (a title, tags) still posts it, and `phx-change` still sees it;
* the server-side value to trust is the stored snapshot, not the posted
  field: the guide shows a changeset that ignores `body` in a collaborative
  form, or reads it from the store;
* `Kotoba.Live.push_content/3` on a collaborative editor is refused (it
  would replace the shared document for everyone); the app changes the
  document with a Yjs update from the server instead, later.

## Uploads, prompts and suggestions

* **Upload markers** are nodes, so they sync: the others see "Uploading
  cat.png…". Each marker records its owner (the Yjs client id); only the
  owner replaces it with the attachment (markers are matched by the
  owner's own list, as today). When a person leaves, the remaining editors
  remove the markers of that client id (awareness tells who left), so a
  marker is never left behind.
* **Prompts** (the `@` menu) and **suggestions** (the Assist panel) are
  local until they insert, which then syncs as any edit.

## Presence

* Carets and selections of the others, in their colors, with their names
  (`@lexical/yjs` awareness and cursors).
* A **people list** next to the toolbar: the names of the people in the
  document, from `Phoenix.Presence` on the server (the source of truth for
  who is there; awareness names are shown on carets only). It is a list
  with a label ("3 people editing"), and the live region says "Ada joined"
  and "Ada left". Carets are `aria-hidden`: a screen reader user reads the
  list.
* The editor shows "Offline, changes will sync" while the socket is down.

## Offline and reconnection

* Edits made while the socket is down stay in the page's Yjs document and
  sync when it reconnects (the provider and the sync protocol do this).
* A reload while offline loses them. Keeping them across reloads
  (`y-indexeddb`) is out of scope for now.
* A LiveView restart does not touch the Channel: the editor keeps its Yjs
  document.

## Scale and limits

* Memory: a document process holds the Yjs document (about 2 to 3 times the
  text, plus tombstones, which compaction on save keeps small) and
  stops a while after the last person leaves.
* One process serialises the updates of one document; that is thousands
  of small updates a second, far above a team typing.
* No limit on people per document in the code; the guide suggests one
  (for example 50) in `authorize/3`.

## Plan

1. **This design** (docs only).
2. **Sync**: the collab bundle, the Channel, `Kotoba.Collab.DocServer` with
   an in-memory store, the dev page with one document in two editors, and
   e2e with two browser contexts (concurrent edits in a paragraph, formats,
   lists, tables, mentions, attachments) in the three engines.
3. **Storage**: `Kotoba.Collab.Store`, the snapshot and its check, the
   bootstrap, the Ecto example.
4. **Presence**: carets, the people list, the announcements, offline state.
5. **Uploads and read-only**: marker ownership and cleanup, read-only
   people, size limits, and the Collaboration guide.

## Open questions for review

1. The separate `kotoba-collab.esm.js` bundle with a Lexical shim (above),
   or collaboration in the main bundle (+52 KB gzip for every app)?
2. `:global` registration by default: good enough, or require a registry
   from the app?
3. A person with `:read` sees live changes: needed now, or later?
4. `push_content/3` refused on a collaborative editor, or turned into a
   server-side Yjs update (needs the node classes on the server, so JSON
   to Yjs in Elixir, like the conversion this design avoids)?
