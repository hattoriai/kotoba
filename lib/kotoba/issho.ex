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
    `tools/0`. A place is a selection (`Kotoba.Issho.Place`). A document's
    changes are events of its room (`events/2`), and a Kotoba editor writes
    Issho's comments (`read_comment/1`).
    """

    use Issho.Binding, engine: Kotoba.Issho.Engine, place: Kotoba.Issho.Place

    alias Kotoba.Collab.Document
    alias Kotoba.Issho.{Comments, Events, Suggestions}

    @doc """
    What a shared editor's document is, for your policy's `document/2`
    (`Issho.Policy`), the same wherever it opens first.

        def document(_identity, "page:" <> _ = id),
          do: Kotoba.Issho.document(store: {MyApp.CollabStore, MyApp.Repo})

    Options: `:store` (required), your `Kotoba.Collab.Store` and its
    context; `:policy`, the document's checks (`:features`, `:nodes`,
    `:validate`), as every accepted transaction must pass them; `:events`,
    `false` for a document whose changes make no events of the room (see
    `events/2`).
    """
    @spec document(keyword()) :: {:ok, map()}
    def document(opts) do
      spec = %{
        engine: __MODULE__,
        opts: Keyword.get(opts, :policy, []),
        store: {Kotoba.Issho.Store, Keyword.fetch!(opts, :store)}
      }

      if Keyword.get(opts, :events, true),
        do: {:ok, Map.put(spec, :events, &events/2)},
        else: {:ok, spec}
    end

    @doc ~S"""
    The events of a change of a shared document (the spec's `:events`,
    see `Issho.Documents.open/4`), which `document/1` gives: once the
    change is saved, they are events of the document's room, with the
    document and the change's author, for agents (`wait_for_events`) and
    for LiveViews (`Issho.Live.subscribe/3`'s `:events`).

      * `"text.block_added"`: `%{block: id, type: type, n: n}`, a block
        that was not there: a new one, or one that came back (an undo).
      * `"text.block_removed"`: `%{block: id, type: type}`, a block that
        went.
      * `"text.changed"`: `%{block: id, type: type, n: n}`, a block whose
        text changed, and that was there before and after. A change of
        format only is not one.

    A block is a paragraph, a heading, a quote, a list item or a code
    block. `id` is its node's id, which stays the same as the text
    changes; `n` is its number, as `read_text` counts them (from 1), after
    the change; `type` is what it is, as `read_text` says it
    (`"paragraph"`, `"h2"`, `"bullet item"`). The text is not in the
    event, as the room's people may not all read each of its documents.

        Issho.Live.subscribe("notebook:7", :self, events: ["text.*"])

        def handle_info({Issho.Live, "event", _room, %Issho.Event{name: "text.changed"} = event}, socket) do
          ...
        end

        # The room's other messages, which :self gets too.
        def handle_info({Issho.Live, _event, _key, _payload}, socket), do: {:noreply, socket}

    An app with events of its own gives both:

        {:ok, spec} = Kotoba.Issho.document(store: {MyApp.CollabStore, MyApp.Repo})
        {:ok, %{spec | events: &(Kotoba.Issho.events(&1, &2) ++ MyApp.Notebooks.events(&1, &2))}}
    """
    @spec events([map()], map()) :: [{String.t(), map()}]
    def events(operations, context), do: Events.events(operations, context)

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
    (`Kotoba.Issho.Place`). At a selection (its anchor and focus apart),
    the suggestion replaces it, on the same words however the text
    changed meanwhile; at a node, or a caret, it goes after its block. An
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
    A Kotoba editor as the comment box of Issho's comments
    (`Issho.Components.comments/1`): its `read`, for the comment's words
    and whom they mention from the box's form params. With
    `comment_prompts/2` and `comment_field/3`:

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

        def handle_event("kotoba:prompt", params, socket) do
          prompts = Kotoba.Issho.comment_prompts(socket.assigns.room, socket.assigns.mentionable)
          {:noreply, Kotoba.Live.handle_prompt(socket, params, prompts)}
        end

    A comment keeps its words as text: a mention of the `@` prompt is
    `"@"` and the person's name in it, as Issho's own comment box writes
    it, and its key is in the comment's mentions, so the person hears of
    it (`"comment.created"`, `Issho.Inbox`). Other mentions are their
    label. Give the box only what text keeps, `[:mentions]`: bold or a
    link's address would be lost.
    """
    @spec read_comment(map()) :: %{body: String.t(), mentions: [String.t()]}
    def read_comment(params), do: Comments.read(params)

    @doc """
    The `@` prompt of a comment box (`read_comment/1`): the room's people,
    those here first, and `mentionable` (`[%{key: "user:42", name: "Ada"}]`,
    as `Issho.Components.comments/1` has it), filtered as the person
    types. A mention's id is the person's key. The same list for the
    editor's `prompts` and for `Kotoba.Live.handle_prompt/3`, in the
    LiveView that is in the room.
    """
    @spec comment_prompts(String.t(), [map()]) :: list()
    def comment_prompts(room, mentionable \\ []),
      do: Comments.prompts(room, mentionable)

    @doc """
    The field of a comment box (`read_comment/1`), from what the `:input`
    slot of `Issho.Components.comments/1` gives: the comment's words as a
    document, a paragraph for each line, each `"@"` and name of someone
    `comment_prompts/2` offers a mention again, so that an edit starts
    from the comment as it is.
    """
    @spec comment_field(map(), String.t(), [map()]) :: Phoenix.HTML.FormField.t()
    def comment_field(input, room, mentionable \\ []),
      do: Comments.field(input, room, mentionable)

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

    With Storehouse, `attach_file` attaches a file the agent sends in
    base64 after a block, checked and stored as an upload is
    (`Kotoba.Attachments.store/2`). `attach:` sets the largest file (10 MB)
    and how it is stored:

        config :kotoba, Kotoba.Issho,
          attach: [max_bytes: 10_000_000, key: &MyApp.Uploads.key/2, preview: &MyApp.Previews.make/2]

    `:storage`, `:key` and `:preview` are `Kotoba.Attachments.store/2`'s.
    The request that carries the file must fit the body size your endpoint
    reads: `Plug.Parsers`' `:length` is 8 MB unless you set it.
    """
    @spec tools() :: [module()]
    def tools,
      do:
        [
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
        ] ++ attach_tools()

    # `attach_file` stores files with Storehouse, an optional dependency.
    if Code.ensure_loaded?(Storehouse) do
      defp attach_tools, do: [Kotoba.Issho.Tools.AttachFile]
    else
      defp attach_tools, do: []
    end
  end
end
