defmodule Kotoba.CollabTest do
  use ExUnit.Case, async: false

  alias Kotoba.Collab
  alias Kotoba.Collab.{Document, Store}
  alias Kotoba.Content

  import Phoenix.LiveViewTest

  @endpoint KotobaTest.Endpoint
  alias Kotoba.Issho.Place

  defmodule Policy do
    @moduledoc false
    @behaviour Issho.Policy

    @impl true
    def authorize(_identity, _document_id, _action), do: :ok

    @impl true
    def document(_identity, "plain:" <> _),
      do:
        Kotoba.Issho.document(store: {Store.Memory, :kotoba_collab_store}, policy: [features: []])

    def document(_identity, _document_id),
      do: Kotoba.Issho.document(store: {Store.Memory, :kotoba_collab_store})
  end

  defmodule CredentialsLive do
    @moduledoc false
    # A LiveView with a shared editor, as an app's: it shows the editor's
    # credentials, or with "editor" in the session the editor itself.
    use Phoenix.LiveView

    on_mount(Issho.Live)

    @impl true
    def mount(_params, %{"issho" => issho} = session, socket) do
      user =
        if session["user"] == "member",
          do: %KotobaTest.Member{id: 7, name: "Ada"},
          else: %{id: 7, name: "Ada", color: "#e84a1c"}

      {:ok,
       assign(socket,
         issho: issho,
         user: user,
         editor: session["editor"],
         credentials: Collab.credentials(issho, user)
       )}
    end

    @impl true
    def render(%{editor: true} = assigns) do
      ~H"""
      <Kotoba.Components.kotoba field={to_form(%{}, as: :post)[:body]} id="body" issho={@issho} user={@user} />
      """
    end

    def render(assigns), do: ~H"<pre id='credentials'>{JSON.encode!(@credentials)}</pre>"
  end

  setup do
    start_supervised!({Store.Memory, name: :kotoba_collab_store})
    %{instance: Issho.Test.start!(policy: Policy)}
  end

  defp insert(id, after_id, value),
    do: %{
      "op" => "insert_text",
      "id" => "seed:2",
      "after" => after_id,
      "atoms" => [%{"id" => id, "text" => value, "attrs" => %{"type" => "text", "version" => 1}}]
    }

  defp stored(id), do: :sys.get_state(:kotoba_collab_store)[id]

  test "a document starts from the content the app has, and saves state and content together",
       %{instance: instance} do
    :ok = Store.Memory.seed(:kotoba_collab_store, "post:1", Content.from_markdown("abc"))

    assert {:ok, %{"revision" => 0, "content" => %Content{text: "abc"}}} =
             Collab.content(instance, "post:1")

    assert {:ok, %{"revision" => 1}} =
             Kotoba.Issho.change(instance, "post:1", [insert("a:1", "seed:2:0", "X")])

    assert %{state: %{"engine" => "kotoba", "revision" => 1}, content: %Content{text: "aXbc"}} =
             stored("post:1")
  end

  test "a retry is applied once, and a transaction id is not used twice", %{instance: instance} do
    :ok = Store.Memory.seed(:kotoba_collab_store, "post:2", Content.from_markdown("abc"))
    {:ok, %{"epoch" => epoch}} = Collab.content(instance, "post:2")

    tx = %{
      "id" => Document.random_id(),
      "epoch" => epoch,
      "base_revision" => 0,
      "ops" => [insert("a:1", nil, "X")]
    }

    assert {:ok, %{"revision" => 1}} = Kotoba.Issho.change(instance, "post:2", tx, author: "7")

    assert {:ok, %{"revision" => 1, "duplicate" => true}} =
             Kotoba.Issho.change(instance, "post:2", tx, author: "7")

    assert {:error, _reused} =
             Kotoba.Issho.change(instance, "post:2", %{tx | "ops" => [insert("a:2", nil, "Y")]},
               author: "7"
             )
  end

  test "a form publishes the exact revision it saw", %{instance: instance} do
    :ok = Store.Memory.seed(:kotoba_collab_store, "post:3", Content.from_markdown("abc"))
    {:ok, %{"epoch" => epoch}} = Collab.content(instance, "post:3")
    {:ok, _} = Kotoba.Issho.change(instance, "post:3", [insert("a:1", "seed:2:0", "X")])
    {:ok, _} = Kotoba.Issho.change(instance, "post:3", [insert("a:2", "a:1", "Y")])

    assert {:ok, %Content{text: "abc"}} =
             Collab.content(instance, "post:3", %{"epoch" => epoch, "revision" => 0})

    assert {:ok, %Content{text: "aXbc"}} =
             Collab.content(instance, "post:3", %{"epoch" => epoch, "revision" => 1})

    assert {:error, :unknown_revision} =
             Collab.content(instance, "post:3", %{"epoch" => "other", "revision" => 1})
  end

  test "the document's policy refuses what it does not allow", %{instance: instance} do
    :ok = Store.Memory.seed(:kotoba_collab_store, "plain:1", Content.from_markdown("abc"))

    bold = %{
      "op" => "set_text_attrs",
      "id" => "seed:2",
      "atoms" => ["seed:2:1"],
      "values" => %{"bold" => true},
      "stamp" => "a:bold"
    }

    assert {:error, {:invalid_content, _}} = Kotoba.Issho.change(instance, "plain:1", [bold])
    assert {:ok, %{"revision" => 0}} = Collab.content(instance, "plain:1")
  end

  test "a document saved by Kotoba before Issho opens, keeps its history, and saves as Issho's",
       %{instance: instance} do
    {:ok, initial} = Document.new(Content.from_markdown("abc"))
    {:ok, state} = Document.apply_ops(initial, [insert("a:1", "seed:2:0", "X")])

    event = %{
      "id" => "t1",
      "revision" => 1,
      "author" => "7",
      "ops" => [insert("a:1", "seed:2:0", "X")]
    }

    envelope = %{"epoch" => "old", "revision" => 1}

    legacy =
      state
      |> Map.merge(envelope)
      |> Map.merge(%{
        "receipts" => %{"t1" => %{"digest" => "d", "revision" => 1, "author" => "7"}},
        "transactions" => [event],
        "initial" => Map.merge(initial, %{"epoch" => "old", "revision" => 0})
      })

    {:ok, content} = Document.validate(state)
    :ok = Store.Memory.save(:kotoba_collab_store, "post:4", nil, legacy, content)

    assert {:ok, %{"epoch" => "old", "revision" => 1, "content" => %Content{text: "aXbc"}}} =
             Collab.content(instance, "post:4")

    assert {:ok, %Content{text: "abc"}} =
             Collab.content(instance, "post:4", %{"epoch" => "old", "revision" => 0})

    assert {:ok, %{"revision" => 2}} =
             Kotoba.Issho.change(instance, "post:4", [insert("a:2", "a:1", "Y")])

    assert %{state: %{"engine" => "kotoba", "epoch" => "old", "revision" => 2}} =
             stored("post:4")
  end

  defp credentials(instance, document, opts \\ []) do
    {user, opts} = Keyword.pop(opts, :user)
    {view, html} = mount_editor(instance, [document: document] ++ opts, %{"user" => user})

    credentials =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#credentials")
      |> LazyHTML.text()
      |> JSON.decode!()

    {view, credentials}
  end

  defp mount_editor(instance, issho, session) do
    {:ok, view, html} =
      live_isolated(Phoenix.ConnTest.build_conn(), CredentialsLive,
        session: Map.put(session, "issho", [instance: instance] ++ issho)
      )

    {view, html}
  end

  test "credentials name the document, its room, the person and their role", %{instance: instance} do
    {_view, credentials} = credentials(instance, "post:5", can: :read)

    assert %{
             "document_id" => "post:5",
             "room" => "post:5",
             "socket" => "/issho/socket",
             "role" => "read",
             "undo" => "editor",
             "follow" => true,
             "user" => %{"id" => "7", "name" => "Ada", "color" => "#e84a1c"}
           } = credentials

    # An editor that takes no part in following, though the room's others do.
    assert {_view, %{"follow" => false}} = credentials(instance, "post:5", follow: false)

    assert {:ok, %Issho.Identity{key: "7"}, :read} =
             Issho.Token.verify(instance, credentials["token"], "post:5")

    {_view, notebook} = credentials(instance, "notebook:7/cell-1")
    assert notebook["room"] == "notebook:7"

    assert {:ok, _identity, :write} =
             Issho.Token.verify(instance, notebook["token"], "notebook:7")

    for wrong <- [[can: :admin], [undo: :always], [room: "post:5"], [max_channels: 0]] do
      assert_raise ArgumentError, fn ->
        Collab.credentials([instance: instance, document: "post:5"] ++ wrong, %{id: 7})
      end
    end
  end

  test "the person is the app's actor: its key and name, and Issho's colour when it has none",
       %{instance: instance} do
    {_view, credentials} = credentials(instance, "post:6", user: "member")

    assert %{"id" => "member:7", "name" => "Ada", "color" => color} = credentials["user"]
    assert color =~ ~r/^var\(--issho-person-[1-8], #2563eb\)$/

    assert {:ok, %Issho.Identity{key: "member:7", name: "Ada"}, :write} =
             Issho.Token.verify(instance, credentials["token"], "post:6")
  end

  test "the LiveView renews an editor's grant of its room, without code of the app's",
       %{instance: instance} do
    {view, _credentials} = credentials(instance, "notebook:8/cell-1")

    render_hook(view, "issho:grant", %{"room" => "notebook:8"})
    assert_reply(view, %{"room" => "notebook:8", "token" => token, "can" => "write"})

    assert {:ok, %Issho.Identity{key: "7"}, :write} =
             Issho.Token.verify(instance, token, "notebook:8")
  end

  test "a shared editor joins with its issho option, and names its document for Issho's page",
       %{instance: instance} do
    {_view, html} =
      mount_editor(instance, [document: "notebook:7/intro", undo: :page], %{"editor" => true})

    editor = html |> LazyHTML.from_fragment() |> LazyHTML.query("#body")
    [collab] = LazyHTML.attribute(editor, "data-collab")

    assert %{"document_id" => "notebook:7/intro", "room" => "notebook:7", "undo" => "page"} =
             JSON.decode!(collab)

    assert LazyHTML.attribute(editor, "data-issho-doc") == ["notebook:7/intro"]
  end

  test "an author is a key, or the app's actor", %{instance: instance} do
    :ok = Store.Memory.seed(:kotoba_collab_store, "post:9", Content.from_markdown("abc"))
    :ok = Issho.Events.subscribe(instance, "post:9")

    assert {:ok, %{"revision" => 1}} =
             Kotoba.Issho.change(instance, "post:9", [insert("a:1", "seed:2:0", "X")],
               author: %KotobaTest.Member{id: 7, name: "Ada"}
             )

    assert_receive {Issho, :event, %Issho.Event{name: "document.changed", by: by}}
    assert %Issho.Identity{key: "member:7", name: "Ada"} = by
  end

  test "a selection is a place Kotoba checks" do
    point = %{"node" => "seed:2", "before" => "seed:2:0"}
    assert :ok = Place.validate(%{"anchor" => point, "focus" => point})
    assert :ok = Place.validate(nil)
    assert {:error, _} = Place.validate(%{"anchor" => point, "focus" => %{}})
  end
end
