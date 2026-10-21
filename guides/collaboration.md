# Collaboration

Kotoba Collab lets people edit the same document, see participant cursors,
and recover local drafts after a reconnect. Forms submit a revision that the
server has accepted and saved.

Collaboration runs on [Issho](https://hex.pm/packages/issho), collaboration
for Phoenix: Issho is the document's authority, the room's people and their
cursors, the connection and the offline drafts; Kotoba is the document, its
operations and the editor. A page with Kotoba and other Issho components (a
canvas, a grid) shares one connection and one list of people.

## Dependencies and JavaScript

Add Issho next to Kotoba:

```elixir
{:kotoba, "~> 0.6"},
{:issho, "~> 0.2"}
```

Enable the optional implementation before connecting the LiveSocket:

```js
import { Kotoba, registerCollaboration } from "kotoba"
import { enableCollaboration } from "kotoba/collab"

enableCollaboration(registerCollaboration)
// Use Kotoba in the LiveSocket's hooks as usual.
```

The collaboration bundle imports `issho`, which esbuild finds in `deps/`
as it finds `phoenix`. For import maps, map `kotoba/collab` to
`kotoba-collab.esm.js` and `issho` to Issho's `issho.esm.js`. Both ESM and
CommonJS collaboration bundles are included. They use the core editor's
Lexical instance through the registration boundary, so Lexical is not
bundled a second time.

## Issho, the policy and storage

Start Issho in your application's supervision tree, after the PubSub:

```elixir
{Issho,
 name: MyApp.Issho,
 pubsub: MyApp.PubSub,
 endpoint: MyAppWeb.Endpoint,
 policy: MyApp.Collaboration}
```

The policy says who may open which document, and what each shared
document is:

```elixir
defmodule MyApp.Collaboration do
  @behaviour Issho.Policy

  @impl true
  def authorize(%Issho.Identity{key: user_id}, document_id, action) do
    if MyApp.Documents.allowed?(user_id, document_id, action),
      do: :ok, else: {:error, :forbidden}
  end

  @impl true
  def document(_identity, _document_id) do
    Kotoba.Collab.document(
      store: {MyApp.CollabStore, MyApp.Repo},
      policy: [features: ~w(bold italic links lists)]
    )
  end
end
```

`action` is `:join` (open the document and see who is here), `:read`
(receive its changes), `:write` (change it) or `:lock`. The identity's
`key` is the `:id` of the user you sign credentials for. `authorize/3`
runs on join, on every message from the browser, and before each change
goes out to a browser: a person whose access you take away stops seeing
the changes, and `Issho.revoke(MyApp.Issho, document_id, user_id)` takes
them out at once.

The document's `:policy` belongs to the shared document, rather than a
browser. Every accepted transaction passes node validation, nesting
rules, URL checks, feature checks, and an optional `:validate` callback
that returns `:ok` or `{:error, reason}`. Configure custom nodes in
`config :kotoba, nodes: [...]` and load their JavaScript modules in every
editor that joins the document.

Implement `Kotoba.Collab.Store`. `load/2` returns
`{:ok, %{state: nil, content: server_owned_initial_content}}` for a document
without editing state, or its complete saved state and content. The browser
cannot seed the shared document. `save/5` must atomically compare the stored
`{epoch, revision}` with `expected` and save **both** state and content.
Return `{:error, :conflict}` for a stale writer. Returning `:ok` before a
durable commit would break the acknowledgement contract.

An Ecto application can keep both fields in a dedicated row. For example,
give `MyApp.SharedDraft` a string primary key, `:epoch` string, `:revision`
integer, `:state` map and `:content` of type `Kotoba.Content`. Its migration
uses `:map` for both `:state` and `:content`:

```elixir
defmodule MyApp.CollabStore do
  @behaviour Kotoba.Collab.Store
  import Ecto.Query
  alias MyApp.SharedDraft

  def load(repo, id) do
    case repo.get(SharedDraft, id) do
      nil -> {:ok, %{state: nil, content: MyApp.Documents.initial_content(id)}}
      row -> {:ok, %{state: row.state, content: row.content}}
    end
  end

  def save(repo, id, expected, state, content) do
    values = %{epoch: state["epoch"], revision: state["revision"],
               state: state, content: content}

    result = case expected do
      nil ->
        repo.insert_all(SharedDraft, [Map.put(values, :id, id)],
          on_conflict: :nothing, conflict_target: [:id])

      {epoch, revision} ->
        query = from d in SharedDraft,
          where: d.id == ^id and d.epoch == ^epoch and d.revision == ^revision
        repo.update_all(query, set: Map.to_list(values))
    end

    case result do
      {1, _} -> :ok
      {0, _} -> {:error, :conflict}
    end
  rescue
    error -> {:error, error}
  end
end
```

This example omits timestamps. Add them to the inserted/updated values if
your schema requires them. Authorize document access before opening or
publishing it. The store's initial-content function must reject unknown
documents if arbitrary creation is inappropriate for your application.

Documents saved by an earlier Kotoba (before Issho) open as they are: the
same epoch, revision, history and receipts, and the next accepted change
saves them in Issho's format, through the same `save/5`.

`Kotoba.Collab.Store.Memory` is supplied for development and tests. It
survives a document process restart, but loses everything on a node restart.
The repository's `/collab` demo uses this store.

## Channel and socket

Mount Issho's channel on a socket of your endpoint:

```elixir
defmodule MyAppWeb.IsshoChannel do
  use Issho.Channel, instance: MyApp.Issho
end

defmodule MyAppWeb.IsshoSocket do
  use Phoenix.Socket
  channel "issho:*", MyAppWeb.IsshoChannel
  def connect(_params, socket, _connect_info), do: {:ok, socket}
  def id(_socket), do: nil
end

# In the endpoint:
socket "/issho/socket", MyAppWeb.IsshoSocket,
  websocket: [max_frame_size: 1_000_000]
```

The channel verifies a signed, document-scoped token before it asks your
policy. Tokens expire after five minutes for new joins. A signed `:read`
role cannot transact, even when the browser enables contenteditable.
Presence is separate from content and never persisted in the document.

The shared editors of a page share one socket per socket URL, each
document with its own channel on it, so a page of many shared editors
opens one WebSocket; two editors of the same document share its channel.
An editor past the socket's channel limit gets another socket. The limit
is `Kotoba.Collab.token/3`'s `:max_channels`, 100 by default, the default
`:max_channels_per_transport` of the Phoenix versions that limit channels
(1.7.24 and later, 1.8.2 and later). If you set a lower
`:max_channels_per_transport` on the socket, pass the same number as
`:max_channels`.

## LiveView and forms

Authorize the authenticated user before signing credentials:

```elixir
collab = Kotoba.Collab.token(MyApp.Issho, document.id,
  user: %{id: user.id, name: user.name, color: "#2563eb"}, role: :write)

socket = assign(socket, collab: collab)
```

```heex
<.kotoba field={@form[:body]} id="body_editor" collab={@collab} />
```

Use `role: :read` for viewers. `readonly` also locks the UI, but authorization
and the signed role enforce permissions. The browser renews credentials
through the LiveView every three minutes and after an expired join. Handle
`kotoba:collab_token`, check the editor/document against your socket assigns,
recheck access, then reply with fresh credentials:

```elixir
def handle_event("kotoba:collab_token", %{"id" => "body_editor", "document_id" => id}, socket) do
  user = socket.assigns.current_user
  # Check id against socket.assigns.document.id and authorize again here.
  credentials = Kotoba.Collab.token(MyApp.Issho, id,
    user: %{id: user.id, name: user.name}, role: :write)
  {:reply, credentials, socket}
end
```

The hidden content input holds the visible local document. It can include
unsent edits, so it is not proof that the authority accepted them. On submit,
the collaboration provider briefly locks editing, waits for all fields in
the form to drain, obtains an accepted revision, and then resubmits. Each
field posts a JSON revision in `kotoba_collab[editor_id]`. Publish that exact
revision through the authority:

```elixir
def handle_event("save", %{"kotoba_collab" => %{"body_editor" => json}}, socket) do
  # Authorize publishing this document independently of editing access.
  with {:ok, revision} <- JSON.decode(json),
       {:ok, content} <- Kotoba.Collab.content(MyApp.Issho,
         socket.assigns.document.id, revision),
       {:ok, document} <- MyApp.Documents.publish(socket.assigns.document, content) do
    {:noreply, assign(socket, document: document)}
  else
    _ -> {:noreply, put_flash(socket, :error, "The document could not be published")}
  end
end
```

The journal can reconstruct an immutable accepted revision, even if another
author edited again before the submit reached LiveView. The application owns
publishing transactions and permissions. An offline form cannot submit an
accepted revision until it reconnects. Custom JavaScript save flows can call
`document.getElementById("body_editor").kotobaCollab.flush()`.

## Merge and history behavior

Transactions carry protocol/schema versions, a document epoch, a unique
transaction ID, their base revision, and operations. Receipts make retries
of the same transaction idempotent. The server orders insertions sharing an
anchor by arrival; a later insertion goes immediately after that anchor.
All participants replay that accepted order. This is a central authority
protocol; independent peers cannot choose their own accepted histories.

Nodes and characters retain identities through moves, link wrapping and
paragraph splits. Deleted characters remain as insertion anchors. Deletions
name the characters actually observed, so they preserve unseen concurrent
insertions. Formatting changes patch individual marks, allowing concurrent
bold and italic to combine. Concurrent writes to the same attribute follow
server order. New text inherits concurrent formatting from its anchor unless
the local edit explicitly changed that attribute.

Undo belongs to the current participant's session. It sends inverse
operations, rather than restoring a whole snapshot. Deletion tags and
attribute/move versions prevent an inverse from removing another person's
deletion or overwriting their later formatting/move. The local undo stack
does not survive a page reload. Upload markers and suggestion previews stay
local; an accepted attachment or suggestion becomes a normal transaction.

## Offline and retention

Each tab keeps its accepted snapshot and immutable pending transactions in
IndexedDB, scoped by origin, document, user and tab session. Reloads reuse
that session. Reconnect joins with pending IDs, learns which already
committed, and overlays the remainder on the latest server snapshot before
resending. When local storage is unavailable, the status says edits are
kept only in the tab. Kotoba does not provide an offline app shell or service
worker.

A deleted target, revoked permission, changed epoch or invalid concurrent
structure can require review. Kotoba freezes the draft and offers a JSON
download; it preserves local work instead of silently replacing it. These
conflicts do not currently have an interactive merge UI.

The v1 store retains the initial snapshot, tombstones, receipts and accepted
journal. It does not compact them. Issho's defaults limit a channel message
to 1 MB (`:max_message_bytes`), a transaction to 1,000 operations, and
stored state to 16 MB (`:max_document_bytes`). Size
limits produce a rejected transaction, not a false acknowledgement. Plan
retention and migrations before accepting unbounded documents. Removing
tombstones or changing an epoch invalidates old pending work.

Named branches, peer replication and branch review are not supported.

Issho's default registry is `:global`, suitable for a single node or a
fully connected BEAM cluster. Storage compare-and-swap rejects stale writers;
it does not promise availability across network partitions. Persistence and
the policy must be shared consistently across nodes.

Backend edits use `Kotoba.Collab.transact/4` with semantic operations through
the same authority. To retry idempotently, pass the original immutable
transaction map, including its original base revision and ID. Whole-document
`Kotoba.Live.push_content/3` is refused by collaborative editors because it
cannot preserve pending identities. Ordinary editors keep their existing
behavior.
