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
{:kotoba, "~> 0.8"},
{:issho, "~> 0.4.2"}
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
    Kotoba.Issho.document(
      store: {MyApp.CollabStore, MyApp.Repo},
      policy: [features: ~w(bold italic links lists)]
    )
  end
end
```

`action` is `:join` (open the document and see who is here), `:read`
(receive its changes), `:write` (change it), `:lock`, or one of Issho's
own: `:comment` (see [Comments](#comments)) and the others of Issho's
guides. The identity's
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
is the editor's `issho` `:max_channels`, 100 by default, the default
`:max_channels_per_transport` of the Phoenix versions that limit channels
(1.7.24 and later, 1.8.2 and later). If you set a lower
`:max_channels_per_transport` on the socket, pass the same number as
`:max_channels`.

## LiveView and forms

Shared editors need Issho's hook in their LiveView, in its `live_session`
or in the LiveView itself:

```elixir
live_session :default, on_mount: [Issho.Live] do
```

The editor joins with its `issho` option, the same keys as every
component of the page (`Issho.Join`: Hakushi's canvas, Masu's grid), and
its `user`:

```heex
<.kotoba
  field={@form[:body]}
  id="body_editor"
  issho={[instance: MyApp.Issho, document: @document.id, can: :write]}
  user={@current_user}
/>
```

The keys: `:instance` and `:document` (required); `:can`, `:write` or
`:read`; `:people`, `false` when the page shows Issho's people list;
`:follow`, `false` for an editor that takes no part in following;
`:on_behalf_of` and `:claims`, for your policy. Kotoba's own: `:undo`
(`:editor`, the default, undoes in the editor; `:page`, the person's last
change on the page; `false`, the browser's own), and `:socket` and
`:max_channels` (above). Any other key raises,
so a typo does not go unnoticed. The editor signs its credentials once
for the LiveView's life.

`user` is your user, as your `Issho.Actor` implementation says them: its
key (`"user:4"`), name and colour, the same person in every block of the
page (a Hakushi canvas, Issho's people list). A map works too:
`%{id: user.id, name: user.name, color: "#2563eb"}`. A person with no
colour gets one of Issho's palette, the same as in Issho's lists.

Use `can: :read` for viewers. `readonly` also locks the UI, but authorization
and the signed role enforce permissions. The credentials are an Issho grant
for the document's room (`Issho.Live.grant/4`): the browser renews it
through the LiveView every three minutes and after an expired join, and
Issho's hook answers, after asking your policy again, so a person whose
access went away gets no new grant. Your LiveView handles no event for it.

The editors of a page whose documents are in one room
(`"notebook:7/cell-1"` and `"notebook:7/cell-2"` are both in
`"notebook:7"`) share the room: one connection, one grant, the same
people, and a person's cursor goes from one editor to the other. The
policy's `authorize/3` is asked about the room.

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

## Agents

An agent edits a shared document as a person does, and the people see it:
its name in the list, its selection in its colour, its text written a
few characters at a time, merged with their own edits. `Kotoba.Issho.tools/0`
gives it the editor's verbs, however it reaches your app:

| Tool | What it does |
|---|---|
| `read_text` | the document's blocks, numbered, with their text and links |
| `select_text` | selects quoted text; the people see the selection |
| `type_text` | types after or before quoted text, at the start or end of a block, or at the selection |
| `replace_text`, `delete_text` | replace or delete quoted text, or the selection |
| `format_text` | bold, italic, underline, strikethrough, code, highlight, subscript, superscript |
| `link_text` | makes quoted text, or the selection, a link |
| `add_block` | a paragraph, a heading or a quote, after a block |
| `move_block` | moves a block after another one, as a block handle does: a list with its items |
| `suggest_text` | suggests text after a block, for the person to accept or reject (an Issho stream, shown by `Kotoba.Issho.suggestions/4`) |
| `copy_text`, `paste_text` | copies with its formatting, pastes in any document of the room |

Text is quoted, not counted, so the agent says what it means. Its
changes are the operations an editor sends, through the same authority,
checks and store.

### How an agent moves

By default an agent moves as a person does, so that the people can follow
it: its caret goes to where it works, it selects text as a drag does,
holds a moment on what it is about to change, then changes it, and it
types at a person's pace, a new block too. Only where it goes is sent
(where it presses, where it lets go): each browser draws the way there,
its caret gliding and the selection sweeping from its start to its end.
It moves with Issho's motion (`Issho.Motion`): only when someone of the
room sees the editor, and within a tool call's time budget; a person
who wants no motion (the app says so, Issho's `data-issho-motion`) sees
its changes land. With Issho's page pointers (`Issho.Components.pointers/1`),
its pointer goes to its caret and glides with it across the page. An app
that wants changes to appear at once says so:

```elixir
# The milliseconds it takes to type a character (0: text appears at once;
# a long text is typed in at most 8 seconds), and whether it goes to where
# it works and drags (false: it is there at once).
config :kotoba, Kotoba.Issho, pace: 25, travel: true
```

### Following someone

Following is Issho's, and the room's: a click on someone in the editor's
people list, or in the page's (`Issho.Components.people/1`), follows
them, and the editor keeps their caret on the screen. On a page of
several blocks in the room, every block follows them, and Issho's
pointers scroll the page to them; an editor alone in its room scrolls to
their caret itself. A key, a click or a scroll in the editor stops
following.

An editor that lists its people says whom it follows: "Following Ada"
with a Stop button, in their colour, and a ring of their colour around
the editor. On an Issho page, where the editor leaves its people to
Issho's list (`people: false`), Issho's list says it.

The look is Issho's, the same as its people list's and every other
block's on the page: the line carries Issho's classes (`issho-following`,
`issho-following-stop`) besides its own (`.kotoba-collab-following`), the
editor carries `data-collab-following` while it follows, and Issho's
properties, on the page, restyle all of them at once:

    :root {
      --issho-following-background: #111827;  /* the person's colour */
      --issho-following-text: #fff;
      --issho-following-ring: none;            /* a ring of the person's colour */
    }

`--collab-follow-color` is the followed person's colour, for your own
rules.

An editor that should take no part in following, though the room's other
blocks do, says so in its `issho`:

    issho={[instance: MyApp.Issho, document: "post:5", follow: false]}

Its people list then follows no one, it shows no one followed, and it
does not move to the caret of whom the room follows.

Give them to your app's own model, through its API, with Issho's room
tools:

```elixir
tools = Issho.Tools.room() ++ Kotoba.Issho.tools()
ctx = Issho.Tool.Context.new(MyApp.Issho, assistant, on_behalf_of: current_user)

Issho.Tools.schemas(tools)                    # the tools of a request to the model
Issho.Tools.call(tools, name, input, ctx)     # each tool use in its answer
```

or serve the same tools to MCP clients (with `{:sake, "~> 0.4"}`):

```elixir
defmodule MyApp.MCP do
  use Issho.MCP,
    name: "my-app",
    version: "1.0.0",
    tools: Issho.Tools.room() ++ Kotoba.Issho.tools()
end
```

See Issho's agents guide for who an agent is, and for whom it acts.

The repository's development app serves them at `/mcp`: with `mix dev`
running and `/collab/notebook` open, connect Claude Code with
`claude mcp add --transport http kotoba-dev http://localhost:4099/mcp`
and ask it to edit the notebook (`notebook/one`, `notebook/two`).

## Comments

Issho's comments (`Issho.Components.comments/1`, see Issho's Comments
guide) take a Kotoba editor as their comment box, in the `:input` slot.
`Kotoba.Issho.read_comment/1` is its `read`: the comment's words and whom
they mention, from the box's form params.

```heex
<Issho.Components.comments id="comments" room={@room} mentionable={@mentionable} read={&Kotoba.Issho.read_comment/1}>
  <:input :let={input}>
    <.kotoba
      field={Kotoba.Issho.comment_field(input, @room, @mentionable)}
      id={input.id}
      label="Comment"
      placeholder={input.placeholder}
      features={[:mentions]}
      prompts={Kotoba.Issho.comment_prompts(@room, @mentionable)}
    />
  </:input>
</Issho.Components.comments>
```

```elixir
def handle_event("kotoba:prompt", params, socket) do
  prompts = Kotoba.Issho.comment_prompts(socket.assigns.room, socket.assigns.mentionable)
  {:noreply, Kotoba.Live.handle_prompt(socket, params, prompts)}
end
```

The LiveView is in the room (a shared editor of the room puts it there,
or `Issho.Live.join/4`), and Issho has a `:store` for its own documents:
a room's comments are one.

* `comment_prompts/2` is the box's `@`: the room's people, those here
  first, and `mentionable` (`[%{key: "user:42", name: "Ada"}]`, people
  who are not here), filtered as the person types. Give the same list to
  the editor and to `Kotoba.Live.handle_prompt/3`.
* `read_comment/1` writes a mention as `"@"` and the person's name, as
  Issho's own box does, and puts their key in the comment's mentions:
  the panel marks it, and the person hears of it (`"comment.created"`,
  their inbox).
* `comment_field/3` is the box's field: a comment's words as a document,
  so that an edit starts from the comment as it is, its `"@"` and names
  mentions again.

A comment keeps its words as text, so give the box only `mentions`: bold
or a link's address would be lost.

## Events

A shared document's changes are events of its room (`Issho.Event`), once
they are saved, with the document and the change's author:

| Event | Data |
| --- | --- |
| `"text.block_added"` | `%{block: id, type: type, n: n}`: a new block, or one back with an undo |
| `"text.block_removed"` | `%{block: id, type: type}`: a block that went |
| `"text.changed"` | `%{block: id, type: type, n: n}`: a block whose text changed (not its format only) |

A block is a paragraph, a heading, a quote, a list item or a code block.
`id` is its node's id, the same however its text changes; `n` its number,
as `read_text` counts them, after the change; `type` what it is, as
`read_text` says it: `"paragraph"`, `"h2"`, `"bullet item"`. The text is
not in the event: the people of a room may not all read each of its
documents.

An agent waits for them:

```text
wait_for_events {"room": "notebook:7", "names": ["text.*"]}
```

and a LiveView hears them:

```elixir
Issho.Live.subscribe("notebook:7", :self, events: ["text.*"])

def handle_info({Issho.Live, "event", _room, %Issho.Event{name: "text.changed"} = event}, socket) do
  ...
end

# The room's other messages, which :self gets too.
def handle_info({Issho.Live, _event, _key, _payload}, socket), do: {:noreply, socket}
```

`Kotoba.Issho.events/2` gives them, and `Kotoba.Issho.document/1` puts it
in the document's spec; `events: false` turns them off. Issho's own
`"document.changed"` comes for every change, as before.

## A person's place

Where a person is in the document, their selection, is in their state
under Issho's `place` key, and so in what an agent sees of them, in
Issho's motion and in what your app keeps of it. Its format is part of
Kotoba's API, and only grows (`Kotoba.Issho.Place`):

```elixir
%{
  "anchor" => %{"node" => node_id, "before" => atom_id | nil},
  "focus" => %{"node" => node_id, "before" => atom_id | nil}
}
```

Each end is a caret in the text node `node`, after the character
`before` (`nil` at the node's start); in a block with no text yet, the
block and an `"offset"`. Ids are the document's own, so a place stays on
the same words however the text around it changes. A caret is a
selection whose two ends are the same.

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

Backend edits use `Kotoba.Issho.change/4` with semantic operations through
the same authority. Its `:author` is a key (`"system"`) or your actor
(`current_user`), and is the change's author everywhere: the journal,
your document hook's `:by` and Issho's `"document.changed"` event. To retry idempotently, pass the original immutable
transaction map, including its original base revision and ID. Whole-document
`Kotoba.Live.push_content/3` is refused by collaborative editors because it
cannot preserve pending identities. Ordinary editors keep their existing
behavior.
