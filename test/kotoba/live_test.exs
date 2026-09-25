defmodule Kotoba.LiveTest do
  # The local storage root is application config.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Kotoba.{Content, TestJSON}
  alias KotobaTest.EditorLive

  @endpoint KotobaTest.Endpoint
  @editor EditorLive.editor_id()
  @png <<0x89, "PNG\r\n", 0x1A, "\n", 13::32, "IHDR", 40::32, 30::32, 8, 6, 0, 0, 0>>

  setup do
    root = Path.join(System.tmp_dir!(), "kotoba-live-#{System.unique_integer([:positive])}")
    Application.put_env(:kotoba, Kotoba.Storage.Local, root: root, url_prefix: "/files")

    on_exit(fn ->
      Application.delete_env(:kotoba, Kotoba.Storage.Local)
      File.rm_rf!(root)
    end)

    {:ok, view, html} = live(build_conn(), "/editor")
    %{view: view, html: html, root: root}
  end

  test "the page renders the editor with its prompts and upload input", %{html: html} do
    doc = LazyHTML.from_document(html)
    editor = LazyHTML.query(doc, "##{@editor}")

    assert LazyHTML.attribute(editor, "phx-hook") == ["Kotoba"]
    assert LazyHTML.attribute(editor, "aria-labelledby") == ["body-label"]

    assert [prompts] = LazyHTML.attribute(editor, "data-prompts")
    assert JSON.decode!(prompts) == %{"@" => "people", "#" => "work"}

    assert [upload] = LazyHTML.attribute(editor, "data-upload")
    assert LazyHTML.query(doc, "input[type=file]##{upload}") |> Enum.count() == 1
  end

  describe "handle_prompt/3" do
    test "pushes the items of the prompt, with the editor id and the query", %{view: view} do
      render_hook(view, "kotoba:prompt", %{
        "v" => 1,
        "id" => @editor,
        "prompt" => "people",
        "query" => "ada"
      })

      assert_push_event(view, "kotoba:prompt_results", %{
        v: 1,
        id: @editor,
        prompt: "people",
        query: "ada",
        items: [%{id: "1", label: "Ada Lovelace", hint: "Engineering"}]
      })
    end

    test "gives the socket to a callback of arity 2", %{view: view} do
      render_hook(view, "kotoba:prompt", %{"id" => @editor, "prompt" => "work", "query" => "q"})

      assert_push_event(view, "kotoba:prompt_results", %{prompt: "work", items: [item]})
      assert item.label == "Work: q"
      assert "w-phx-" <> _rest = item.id
    end

    test "gives no items for an unknown prompt", %{view: view} do
      render_hook(view, "kotoba:prompt", %{"id" => @editor, "prompt" => "nope", "query" => "a"})
      assert_push_event(view, "kotoba:prompt_results", %{prompt: "nope", items: []})
    end

    test "gives no items for a query that is too long", %{view: view} do
      query = String.duplicate("a", 65)

      render_hook(view, "kotoba:prompt", %{
        "id" => @editor,
        "prompt" => "people",
        "query" => query
      })

      assert_push_event(view, "kotoba:prompt_results", %{query: ^query, items: []})
    end

    test "ignores a payload without a prompt", %{view: view} do
      render_hook(view, "kotoba:prompt", %{"id" => @editor})
      refute_push_event(view, "kotoba:prompt_results", %{})
    end
  end

  describe "server pushes" do
    test "push_content/3 pushes set_content with the document", %{view: view} do
      content = Content.from_markdown("Hello")
      send(view.pid, {:push_content, content})

      assert_push_event(view, "set_content", %{v: 1, id: @editor, doc: doc})
      assert doc == content.doc
    end

    test "push_content/3 casts a document envelope", %{view: view} do
      envelope = TestJSON.envelope([TestJSON.paragraph([TestJSON.text("x")])])
      send(view.pid, {:push_content, envelope})

      assert_push_event(view, "set_content", %{id: @editor, doc: %{"kotoba" => 1}})
    end

    test "insert_node/3 pushes the node in its JSON form", %{view: view} do
      node = %Kotoba.Nodes.Attachment{
        key: "k",
        url: "/files/k",
        name: "a.pdf",
        content_type: "application/pdf",
        bytes: 3
      }

      send(view.pid, {:insert_node, node})

      assert_push_event(view, "insert_node", %{v: 1, id: @editor, node: json})

      assert json == %{
               "type" => "attachment",
               "version" => 1,
               "key" => "k",
               "url" => "/files/k",
               "name" => "a.pdf",
               "contentType" => "application/pdf",
               "bytes" => 3
             }
    end

    test "insert_node/3 pushes a mention", %{view: view} do
      send(view.pid, {:insert_node, %Kotoba.Nodes.Mention{kind: "people", id: "1", label: "Ada"}})

      assert_push_event(view, "insert_node", %{
        node: %{"type" => "mention", "kind" => "people", "id" => "1", "label" => "Ada"}
      })
    end

    test "set_readonly/3, focus/2 and remove_marker/3", %{view: view} do
      send(view.pid, {:set_readonly, true})
      assert_push_event(view, "set_readonly", %{v: 1, id: @editor, readonly: true})

      send(view.pid, :focus)
      assert_push_event(view, "focus", %{v: 1, id: @editor})

      send(view.pid, {:remove_marker, "3"})
      assert_push_event(view, "remove_marker", %{v: 1, id: @editor, ref: "3"})
    end
  end

  describe "consume_uploads/4" do
    test "stores an image and pushes an attachment node for its entry", %{view: view, root: root} do
      upload =
        file_input(view, "#post-form", :attachments, [
          %{name: "My cat.png", content: @png, type: "image/png"}
        ])

      [entry_ref] = entry_refs(upload)
      render_upload(upload, "My cat.png")

      assert_push_event(view, "insert_node", %{id: @editor, ref: ^entry_ref, node: node})

      assert %{
               "type" => "attachment",
               "name" => "My cat.png",
               "contentType" => "image/png",
               "bytes" => bytes,
               "width" => 40,
               "height" => 30,
               "key" => key,
               "url" => url
             } = node

      assert bytes == byte_size(@png)
      assert key =~ ~r"\A\d{4}/\d{2}/[0-9a-f-]{36}-My_cat\.png\z"
      assert url == "/files/" <> key
      assert File.read!(Path.join(root, key)) == @png
    end

    test "does not trust the browser's image type", %{view: view} do
      upload =
        file_input(view, "#post-form", :attachments, [
          %{name: "fake.png", content: "<svg onload=alert(1)>", type: "image/png"}
        ])

      render_upload(upload, "fake.png")

      assert_push_event(view, "insert_node", %{
        node: %{"contentType" => "application/octet-stream"} = node
      })

      refute Map.has_key?(node, "width")
    end

    test "removes the marker when the storage fails" do
      {:ok, view, _html} = live(build_conn(), "/editor?storage=failing")

      upload =
        file_input(view, "#post-form", :attachments, [
          %{name: "notes.txt", content: "hello", type: "text/plain"}
        ])

      [entry_ref] = entry_refs(upload)
      render_upload(upload, "notes.txt")

      assert_push_event(view, "remove_marker", %{id: @editor, ref: ^entry_ref})
      refute_push_event(view, "insert_node", %{})
    end

    test "cancels an entry that fails validation and removes its marker", %{view: view} do
      upload =
        file_input(view, "#post-form", :attachments, [
          %{name: "big.txt", content: String.duplicate("a", 2_000), type: "text/plain"}
        ])

      [entry_ref] = entry_refs(upload)
      assert {:ok, %{errors: %{^entry_ref => [:too_large]}}} = preflight_upload(upload)

      view |> element("#post-form") |> render_change(%{"post" => %{"body" => ""}})

      assert_push_event(view, "remove_marker", %{id: @editor, ref: ^entry_ref})
      refute render(view) =~ "big.txt"
    end
  end

  defp entry_refs(upload), do: Enum.map(upload.entries, & &1["ref"])
end
