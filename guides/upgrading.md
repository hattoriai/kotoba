# Upgrading

## To Kotoba 0.7

Kotoba 0.7 runs on [Issho](https://hex.pm/packages/issho) 0.3, which makes
agents move as people do and following someone the room's, across every
block of a page. An editor that is not shared needs nothing.

### What changes

| 0.6 | 0.7 |
| --- | --- |
| `{:issho, "~> 0.2"}` | `{:issho, "~> 0.3"}` |
| an agent's edits appeared at once | it goes to the text, selects as a drag does, holds a moment, and types at a person's pace (`config :kotoba, Kotoba.Issho, pace: 25, travel: true`), when someone sees it (`Issho.Motion`) |
| no following | the editor's people list follows on a click, and the editor follows the one followed in the room to their caret |

### Steps

1. **Update** `{:kotoba, "~> 0.7"}` and `{:issho, "~> 0.3"}`.
2. **For changes that appear at once**, as in 0.6:
   `config :kotoba, Kotoba.Issho, pace: 0, travel: false` (or Issho's
   `config :issho, Issho.Motion, travel: false` for every component).
3. **On a page of several blocks**, add Issho's pointers
   (`Issho.Components.pointers/1`): an agent's pointer goes from block to
   block, the page follows the one followed, and a person's motion is the
   app's to say (`motion` on the pointers).

## To Kotoba 0.6

Kotoba 0.6 moves shared editing onto [Issho](https://hex.pm/packages/issho),
collaboration for Phoenix, which Hakushi's canvases were built on, and
onto which Masu 0.4 moves its grids' people. An editor that is not shared
works exactly as before: the editor, its content, forms, rendering,
uploads, prompts and custom nodes need nothing.

This guide is for an app with shared editors (`collab` on `<.kotoba>`).

### Why

Kotoba 0.5 brought its own collaboration: a document supervisor, a
channel, a socket, credentials and their renewal, cursors and people.
That served one editor of one document on a page, and it was all
Kotoba's:

- **A page has one set of people.** A page with two editors, or an
  editor beside a grid or a canvas, showed a list of people for each, a
  connection for each, and a color of each for one person. In an Issho
  room the page has one connection, one list (`Issho.Components.people/1`),
  one color for each person in every part of the page, and a person's
  cursor goes from one editor to the next (`"notebook:7/cell-1"` and
  `"notebook:7/cell-2"` are in one room).
- **One policy for the page.** Your channel's `authorize/3` was Kotoba's
  own. Issho's policy (`Issho.Policy`) says who may join, read, write and
  lock in a room, for every component of it, on join and again as they
  work, and renews the credentials it granted only while it still lets
  the person in: your LiveView handles no `kotoba:collab_token` event.
- **Agents.** In an Issho room an agent is someone: it reads the
  document, selects text (the people see its selection), types a few
  characters at a time, formats, links, copies and pastes, as a person
  does with the editor, and its changes merge with everyone's
  (`Kotoba.Issho.tools/0`). It reaches your app however you like: MCP
  (`Issho.MCP`), your app's own model (`Issho.Tools`), a job.
- **Undo is the page's.** `undo: :page` takes back the person's last
  change on the page, in whichever editor or component they made it.
- **The page as a live space.** Issho draws each person's pointer over
  the whole page (`Issho.Components.pointers/1`), and an agent at work in
  a document at its editor.
- **What comes next is Issho's.** Following someone from page to page,
  a live canvas or grid inside a text, rich text inside a canvas's node,
  a document of another app or another cluster: Issho's roadmap, which
  a shared editor gets as it comes, rather than each library building its
  own.

Kotoba keeps what is Kotoba's: the document, its operations and merge
rules, its policy of nodes and features, the editor, the offline drafts
and the form flow. Issho is the document's authority, the room's people
and their cursors, and the connection.

### What changes

| 0.5 | 0.6 |
| --- | --- |
| `{Kotoba.Collab.Supervisor, name:, store:, policy:}` | `{Issho, name: MyApp.Issho, pubsub:, endpoint:, policy: MyApp.Collaboration}`, whose `document/2` gives `Kotoba.Collab.document(store:, policy:)` |
| your channel's `authorize(socket, document_id, action)` | your policy's `authorize(identity, room, action)` (`identity.key` is the user's id) |
| `use Kotoba.Collab.Channel` and `channel "kotoba:*"` at `/kotoba/socket` | `use Issho.Channel` and `channel "issho:*"` at `/issho/socket` |
| `Kotoba.Collab.token(socket, id, opts)` | `Kotoba.Collab.token(MyApp.Issho, id, opts)` |
| `handle_event("kotoba:collab_token", ...)` | none: `on_mount Issho.Live` renews the grant, asking your policy |
| `Kotoba.Collab.content(MyApp.CollabSupervisor, ...)`, `transact/4` | the same, with `MyApp.Issho` |
| an import map with `kotoba/collab` | `kotoba/collab` and `issho` |

`Kotoba.Collab.Store` is unchanged. Documents it saved before open as
they are, with their epoch, revision, history and receipts, and are saved
in Issho's form with their next change. The editors' browsers keep their
offline drafts.

### Steps

1. **Add Issho** to your dependencies:

   ```elixir
   {:kotoba, "~> 0.6"},
   {:issho, "~> 0.2"}
   ```

2. **Replace the supervisor with Issho**, in your supervision tree after
   the PubSub:

   ```diff
   -{Kotoba.Collab.Supervisor,
   - name: MyApp.CollabSupervisor,
   - store: {MyApp.CollabStore, MyApp.Repo},
   - policy: [features: ~w(bold italic links lists)]}
   +{Issho,
   + name: MyApp.Issho,
   + pubsub: MyApp.PubSub,
   + endpoint: MyAppWeb.Endpoint,
   + policy: MyApp.Collaboration}
   ```

3. **Move your channel's authorization into a policy**, which says what
   each document is too:

   ```elixir
   defmodule MyApp.Collaboration do
     @behaviour Issho.Policy

     @impl true
     def authorize(%Issho.Identity{key: user_id}, room, action) do
       if MyApp.Documents.allowed?(user_id, room, action),
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

   The policy is asked about the room: the document's id, or the part of
   it before the first `"/"` (`"notebook:7"` for `"notebook:7/cell-1"`).
   Its actions are `:join`, `:read`, `:write` and `:lock`.

4. **Replace the channel and the socket**:

   ```diff
    defmodule MyAppWeb.CollabChannel do
   -  use Kotoba.Collab.Channel, supervisor: MyApp.CollabSupervisor
   -  def authorize(socket, document_id, action), do: ...
   +  use Issho.Channel, instance: MyApp.Issho
    end

    defmodule MyAppWeb.CollabSocket do
      use Phoenix.Socket
   -  channel "kotoba:*", MyAppWeb.CollabChannel
   +  channel "issho:*", MyAppWeb.CollabChannel
      def connect(_params, socket, _connect_info), do: {:ok, socket}
      def id(_socket), do: nil
    end

    # In the endpoint:
   -socket "/kotoba/socket", MyAppWeb.CollabSocket,
   +socket "/issho/socket", MyAppWeb.CollabSocket,
      websocket: [max_frame_size: 1_000_000]
   ```

5. **Sign credentials with the instance**, add Issho's hook, and remove
   the renewal event:

   ```diff
   +on_mount Issho.Live

   -collab = Kotoba.Collab.token(socket, document.id, user: user, role: :write)
   +collab = Kotoba.Collab.token(MyApp.Issho, document.id, user: user, role: :write)

   -def handle_event("kotoba:collab_token", params, socket), do: ...
   ```

   and publish with it:

   ```diff
   -Kotoba.Collab.content(MyApp.CollabSupervisor, document.id, revision)
   +Kotoba.Collab.content(MyApp.Issho, document.id, revision)
   ```

6. **Map `issho`** in an import map, next to `kotoba/collab`; with esbuild
   it is found in `deps/`, as `phoenix` is.

### Then

- On a page of several editors, put their documents in one room
  (`"notebook:7/cell-1"`, `"notebook:7/cell-2"`), list its people once
  with `Issho.Components.people/1`, and give the editors `people: false`.
- Show the pointers of the page's people: `Issho.Components.pointers/1`.
- Choose undo: `undo: :page` for the person's last change on the page.
- Give agents the editor's tools: `Kotoba.Issho.tools/0`, with Issho's
  room tools (see [Collaboration](collaboration.md#agents)).
