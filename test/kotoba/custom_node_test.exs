defmodule Kotoba.CustomNodeTest do
  # async: false because some tests set `config :kotoba, nodes:`.
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Kotoba.{Components, Content, Document, Nodes, Renderer, Sanitizer}
  alias Kotoba.Nodes.Unknown
  alias KotobaTest.Nodes.Pointer

  setup do
    previous = Application.fetch_env(:kotoba, :nodes)

    on_exit(fn ->
      case previous do
        {:ok, nodes} -> Application.put_env(:kotoba, :nodes, nodes)
        :error -> Application.delete_env(:kotoba, :nodes)
      end
    end)

    Application.delete_env(:kotoba, :nodes)
    :ok
  end

  defp pointer(target, label \\ "The spec") do
    %{"type" => "test-pointer", "version" => 1, "target" => target, "label" => label}
  end

  defp paragraph(children) do
    %{
      "type" => "paragraph",
      "version" => 1,
      "direction" => nil,
      "format" => "",
      "indent" => 0,
      "textFormat" => 0,
      "textStyle" => "",
      "children" => children
    }
  end

  defp text(text) do
    %{
      "type" => "text",
      "version" => 1,
      "detail" => 0,
      "format" => 0,
      "mode" => "normal",
      "style" => "",
      "text" => text
    }
  end

  defp envelope(children) do
    %{
      "kotoba" => 1,
      "lexical" => "0.51",
      "root" => %{
        "type" => "root",
        "version" => 1,
        "direction" => nil,
        "format" => "",
        "indent" => 0,
        "children" => children
      }
    }
  end

  defp html(doc, opts \\ []), do: doc |> Renderer.to_html(opts) |> Phoenix.HTML.safe_to_string()

  defp document do
    envelope([
      paragraph([text("See "), pointer("https://example.com/spec")]),
      pointer("/docs/intro", "Intro")
    ])
  end

  describe "the Pointer node" do
    test "is a Kotoba.Node with its own type" do
      assert Kotoba.Node.node_module?(Pointer)
      assert Pointer.type() == "test-pointer"
      assert Pointer.kind() == :decorator
      assert Enum.map(Pointer.fields(), & &1.key) == ["target", "label", "version"]
    end

    test "parses with the nodes option and writes the same JSON" do
      assert {:ok, doc} = Document.parse(document(), nodes: [Pointer])

      assert [
               %Nodes.Paragraph{
                 children: [%Nodes.Text{}, %Pointer{target: "https://example.com/spec"}]
               },
               %Pointer{target: "/docs/intro", label: "Intro"}
             ] = doc.root.children

      assert Document.to_json(doc) == document()
    end

    test "parses as a JSON string" do
      assert {:ok, doc} = Document.parse(JSON.encode!(document()), nodes: [Pointer])
      assert [_paragraph, %Pointer{}] = doc.root.children
    end

    test "refuses a pointer without a target" do
      doc = envelope([Map.delete(pointer("/x"), "target")])
      assert {:error, [message]} = Document.parse(doc, nodes: [Pointer])
      assert message =~ "target"
    end

    test "renders HTML, text and Markdown" do
      {:ok, doc} = Document.parse(document(), nodes: [Pointer])

      assert html(doc) ==
               ~s(<p>See <a class="test-pointer" href="https://example.com/spec">The spec</a></p>) <>
                 ~s(<a class="test-pointer" href="/docs/intro">Intro</a>)

      assert Renderer.to_text(doc) == "See The spec\nIntro"

      assert Renderer.to_markdown(doc) ==
               "See [The spec](https://example.com/spec)\n\n[Intro](/docs/intro)"
    end

    test "escapes the label" do
      {:ok, doc} = Document.parse(envelope([pointer("/x", "<b>*bold*</b>")]), nodes: [Pointer])

      assert html(doc) == ~s(<a class="test-pointer" href="/x">&lt;b&gt;*bold*&lt;/b&gt;</a>)
      assert Renderer.to_markdown(doc) == "[\\<b>\\*bold\\*\\</b>](/x)"
    end

    test "renders a javascript: target as text" do
      {:ok, doc} =
        Document.parse(envelope([paragraph([pointer("javascript:alert(1)", "Click")])]),
          nodes: [Pointer]
        )

      assert html(doc) == "<p>Click</p>"
      refute html(doc) =~ "javascript"
      assert Renderer.to_markdown(doc) == "Click"
      assert Renderer.to_text(doc) == "Click"
    end

    test "renders as text under the untrusted policy" do
      {:ok, doc} = Document.parse(document(), nodes: [Pointer])
      assert html(doc, policy: :untrusted) == "<p>See The spec</p>Intro"
    end

    test "passes the sanitizer, and a bad label renders as unknown" do
      {:ok, doc} = Document.parse(document(), nodes: [Pointer])
      [_paragraph, top] = doc.root.children
      assert Sanitizer.check(top, doc.root) == :ok

      bad = %{top | label: "a\u0000b"}
      assert {:error, "label has a control character"} = Sanitizer.check(bad, doc.root)

      doc = %{doc | root: %{doc.root | children: [bad]}}
      assert html(doc) == ~s(<span class="kotoba-unknown" data-type="test-pointer"></span>)
      assert Renderer.to_text(doc) == ""
    end

    test "without the node it stays an unknown node, and its JSON is kept" do
      {:ok, doc} = Document.parse(document())
      assert [_paragraph, %Unknown{type: "test-pointer"}] = doc.root.children
      assert html(doc) =~ ~s(<span class="kotoba-unknown" data-type="test-pointer"></span>)
      assert Document.to_json(doc) == document()
    end
  end

  describe "the registry" do
    test "a configured node parses and renders with no option" do
      Application.put_env(:kotoba, :nodes, [Pointer])

      assert Nodes.registry()["test-pointer"] == Pointer
      assert {:ok, doc} = Document.parse(document())
      assert [_paragraph, %Pointer{}] = doc.root.children
      assert html(doc) =~ ~s(<a class="test-pointer" href="/docs/intro">Intro</a>)
    end

    test "Content.cast/1 renders a configured node into the cache" do
      Application.put_env(:kotoba, :nodes, [Pointer])

      assert {:ok, content} = Content.cast(JSON.encode!(document()))

      assert content.html =~
               ~s(<a class="test-pointer" href="https://example.com/spec">The spec</a>)

      assert content.text == "See The spec\nIntro"
      assert content.doc == document()
    end

    test "Content.cast/1 keeps a node that is not configured, and rerender/2 renders it" do
      assert {:ok, content} = Content.cast(document())
      assert content.html =~ ~s(data-type="test-pointer")
      assert content.doc == document()

      content = Content.rerender(content, nodes: [Pointer])
      assert content.html =~ ~s(<a class="test-pointer" href="/docs/intro">Intro</a>)
    end

    test "the component's nodes render a node that is not configured" do
      {:ok, content} = Content.cast(document())

      html =
        render_component(&Components.kotoba_content/1,
          content: content,
          nodes: [{Pointer, "/assets/kotoba/nodes/pointer.js"}]
        )

      assert html =~ ~s(<a class="test-pointer" href="https://example.com/spec">The spec</a>)
      refute html =~ "kotoba-unknown"
    end

    test "the editor gets the URL of the node module" do
      form = Phoenix.Component.to_form(%{"body" => nil}, as: :post)

      html =
        render_component(&Components.kotoba/1,
          field: form[:body],
          id: "post-body",
          nodes: [{Pointer, "/assets/kotoba/nodes/pointer.js"}]
        )

      assert html =~ ~s(data-nodes="/assets/kotoba/nodes/pointer.js")
    end

    test "the configured nodes and the caller nodes are merged with the built-ins" do
      Application.put_env(:kotoba, :nodes, [Pointer])
      registry = Nodes.registry([KotobaTest.Nodes.Pointer])
      assert registry["test-pointer"] == Pointer
      assert registry["mention"] == Nodes.Mention
      assert map_size(registry) == length(Nodes.built_in()) + 1
    end
  end
end
