if Code.ensure_loaded?(Issho.Binding) do
  defmodule Kotoba.Issho.Engine do
    @moduledoc false
    # The document's state and operations: Kotoba.Collab.Document. Issho
    # keeps the epoch, revision, receipts and journal around it.
    @behaviour Issho.Engine

    alias Kotoba.Collab.Document

    @impl true
    def name, do: "kotoba"

    @impl true
    def version, do: 1

    @impl true
    def init(content, opts), do: Document.new(content, policy(opts))

    @impl true
    def apply(state, ops, _opts), do: Document.apply_ops(state, ops)

    @impl true
    def validate(state, opts), do: Document.validate(state, policy(opts))

    @impl true
    def upgrade(stored), do: Document.upgrade(stored)

    defp policy(opts), do: Keyword.drop(opts, [:author])
  end

  defmodule Kotoba.Issho.Place do
    @moduledoc """
    A place in a Kotoba document: a selection, kept and sent as it is (in
    a person's state, in an agent's motion, and in what an app keeps of
    them), so its format is part of Kotoba's public API and only grows.

        %{
          "anchor" => %{"node" => node_id, "before" => atom_id | nil},
          "focus" => %{"node" => node_id, "before" => atom_id | nil}
        }

    Each end is a caret: in the text node `node`, after the character
    `before` (`nil` at the node's start). In a block with no text yet, a
    point is the block and an `"offset"` (`%{"node" => block_id, "before"
    => nil, "offset" => 0}`). Ids are the document's own (at most 160
    bytes), so a place stays on the same words however the text around it
    changes. A caret is a selection whose anchor and focus are the same.
    """
    @behaviour Issho.Place

    @impl true
    def validate(nil), do: :ok

    def validate(%{"anchor" => anchor, "focus" => focus}) do
      if point?(anchor) and point?(focus), do: :ok, else: {:error, :invalid_selection}
    end

    def validate(_other), do: {:error, :invalid_selection}

    defp point?(%{"node" => node, "before" => before} = point),
      do:
        id?(node) and (is_nil(before) or id?(before)) and
          (not Map.has_key?(point, "offset") or
             (is_integer(point["offset"]) and point["offset"] >= 0))

    defp point?(_other), do: false

    defp id?(value), do: is_binary(value) and byte_size(value) <= 160
  end

  defmodule Kotoba.Issho.Store do
    @moduledoc false
    # An Issho store on the app's Kotoba.Collab.Store: the same rows, and
    # the content the app has for a document no one has edited together.
    @behaviour Issho.Store

    @impl true
    def load({store, context}, id) do
      case store.load(context, id) do
        {:ok, %{state: nil, content: content}} -> {:ok, {:initial, content}}
        {:ok, %{state: state}} -> {:ok, state}
        {:error, _reason} = error -> error
      end
    end

    @impl true
    def save({store, context}, id, expected, document, content),
      do: store.save(context, id, expected, document, content)
  end

  defmodule Kotoba.Issho do
    @moduledoc """
    Kotoba's binding for [Issho](https://hex.pm/packages/issho): a shared
    editor's document is an Issho document, its engine Kotoba's semantic
    operations (`Kotoba.Collab.Document`), and a person's place their
    selection in it.

    Name it as a document's engine through `document/1`, in your policy;
    change a document from your own code with `change/4`; give agents
    `tools/0`. A place is a selection (`Kotoba.Issho.Place`).
    """

    use Issho.Binding, engine: Kotoba.Issho.Engine, place: Kotoba.Issho.Place

    alias Kotoba.Collab.Document
    alias Kotoba.Issho.Suggestions

    @doc """
    What a shared editor's document is, for your policy's `document/2`
    (`Issho.Policy`), the same wherever it opens first.

        def document(_identity, "page:" <> _ = id),
          do: Kotoba.Issho.document(store: {MyApp.CollabStore, MyApp.Repo})

    Options: `:store` (required), your `Kotoba.Collab.Store` and its
    context; `:policy`, the document's checks (`:features`, `:nodes`,
    `:validate`), as every accepted transaction must pass them.
    """
    @spec document(keyword()) :: {:ok, map()}
    def document(opts) do
      {:ok,
       %{
         engine: __MODULE__,
         opts: Keyword.get(opts, :policy, []),
         store: {Kotoba.Issho.Store, Keyword.fetch!(opts, :store)}
       }}
    end

    @doc """
    Changes a shared document from your own code (a job, an import),
    through the same authority, checks and store as the editors' changes:
    operations (`Kotoba.Collab.Document`), or a transaction map (with its
    `"id"` and `"base_revision"`) to retry one idempotently.

    Options: `:author`, who made it, as the document's hook and history
    know them: an actor (`Issho.Actor`, your user or an agent) or a key
    (`"server"` unless given, a service); `:id`, the transaction's.
    """
    @spec change(atom(), String.t(), list() | map(), keyword()) :: {:ok, map()} | {:error, term()}
    def change(instance, document_id, operations_or_transaction, opts \\ [])

    def change(instance, document_id, %{"ops" => _} = transaction, opts) do
      with {:ok, pid} <- Issho.Documents.open(instance, document_id),
           do:
             Issho.Authority.commit(
               pid,
               transaction,
               author(Keyword.get(opts, :author, "server"))
             )
    end

    def change(instance, document_id, operations, opts) when is_list(operations) do
      opts = Keyword.put_new_lazy(opts, :id, &Document.random_id/0)
      Issho.transact(instance, document_id, operations, opts)
    end

    defp author(key) when is_binary(key), do: key
    defp author(actor), do: Issho.Identity.new(actor)

    @doc ~S"""
    Shows Issho's streams (`Issho.Streams`) as suggestions in this
    LiveView's shared editors: an answer, a draft, an agent's proposal,
    written by a process of your app or an agent, for this person (or the
    room), at a place of an editor's document. Each shows in its editor as
    a suggestion (see the [Suggestions](suggestions.md) guide), after the
    block of its place, as it comes; a page that mounts while it is
    written picks it up where it got to. Accept puts it in the document,
    as the person's change; Accept, Reject and Stop close the stream
    (`"accepted"`, `"rejected"`, `"stopped"`), and a page that goes away
    does not. A stream closed elsewhere (accepted in another tab) goes.

        on_mount Issho.Live

        def mount(_params, _session, socket) do
          issho = [instance: MyApp.Issho, document: "notebook:7/intro"]
          socket = assign(socket, issho: issho, user: socket.assigns.current_user)
          {:ok, Kotoba.Issho.suggestions(socket, socket.assigns.user, %{"intro_editor" => issho})}
        end

        # <.kotoba field={@form[:intro]} id="intro_editor" issho={@issho} user={@user} assist={true} />

    `editors` maps each editor's id to its `issho` options (the
    `:instance` and the `:document`). The editors need `assist` (`true`
    for no menu), for the person's answers to reach the LiveView. The
    LiveView joins each document's room (`Issho.Live.join/4`, with
    `on_mount Issho.Live`), and handles the streams' messages and the
    editors' `kotoba:suggestion` events itself (`attach_hook/4`).

    A stream's place is `%{"doc" => document, "at" => at}`, `at` a node
    id (`%{"node" => id}`, a block's or a text's) or a Kotoba selection
    (`Kotoba.Issho.Place`): the suggestion goes after its block. An
    editor shows one at a time; the others wait their turn. A stream's
    label is its `meta`'s `"label"`, else its kind.

    Options:

      * `:kinds` - the kinds of stream that are suggestions (all by default).
      * `:display` - `:panel` (the default) or `:inline`, as
        `Kotoba.Live.stream_start/4`.
      * `:pass` - `true` gives your `handle_info/2` the messages of the
        room's other streams; by default they stop here.

    With `Kotoba.Issho.tools/0`, an agent writes one with `suggest_text`.
    Without Issho, `Kotoba.Live.stream_resume/5` and the Suggestions
    guide's recipe do the same with a process of your app.
    """
    @spec suggestions(Phoenix.LiveView.Socket.t(), term(), map() | keyword(), keyword()) ::
            Phoenix.LiveView.Socket.t()
    def suggestions(socket, user, editors, opts \\ []),
      do: Suggestions.attach(socket, user, editors, opts)

    @doc ~S"""
    Kotoba's tools for agents (`Issho.Tool`): an agent reads a shared
    document, selects text (the people see its selection), types (they see
    it written), replaces, deletes, formats, links, adds and moves
    blocks, copies and pastes, as a person does in the editor, and its
    changes merge with theirs; or it suggests text that the person takes
    or leaves (`suggest_text`, see `suggestions/4`). Give them to your
    app's model (`Issho.Tools`), or serve them to MCP clients
    (`Issho.MCP`), with Issho's room tools:

        tools = Issho.Tools.room() ++ Kotoba.Issho.tools()

    A tool names its document by id (`"notebook:7/intro"`); the room is the
    part before the `"/"`. Text is quoted, not counted: `select_text` with
    the words, then `link_text` with no text links the selection.

    An agent moves as a person does, so that the people follow it: its
    caret goes to where it works, it selects as a drag does and holds a
    moment before it changes the selection, and it types at a person's
    pace. Only where it goes is sent; each browser draws the way there.
    For changes that appear at once:

        config :kotoba, Kotoba.Issho, pace: 0, travel: false

    `pace`: the milliseconds it takes to type a character (25; a long text
    is typed in at most 8 seconds). `travel`: whether it goes to where it
    works and drags (true).
    """
    @spec tools() :: [module()]
    def tools,
      do: [
        Kotoba.Issho.Tools.Read,
        Kotoba.Issho.Tools.Select,
        Kotoba.Issho.Tools.Type,
        Kotoba.Issho.Tools.Replace,
        Kotoba.Issho.Tools.Delete,
        Kotoba.Issho.Tools.Format,
        Kotoba.Issho.Tools.Link,
        Kotoba.Issho.Tools.AddBlock,
        Kotoba.Issho.Tools.MoveBlock,
        Kotoba.Issho.Tools.SuggestText,
        Kotoba.Issho.Tools.Copy,
        Kotoba.Issho.Tools.Paste
      ]
  end
end
