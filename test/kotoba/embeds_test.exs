defmodule Kotoba.EmbedsTest do
  # A test puts the :embed_from_markdown config.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Kotoba.TestJSON

  @endpoint KotobaTest.Endpoint

  defp open(query \\ "") do
    {:ok, view, html} = live(build_conn(), "/embeds" <> query)
    {view, html}
  end

  # What the editor sends when an embed's slot comes and goes.
  defp embeds(view, payload) do
    view
    |> with_target("#body-embeds")
    |> render_hook("kotoba:embeds", Map.merge(%{"v" => 1, "id" => "body"}, payload))
  end

  defp mount(view, key, kind \\ "counter", ref \\ "1") do
    embeds(view, %{
      "action" => "mount",
      "slot" => "body-embed-#{key}",
      "kind" => kind,
      "ref" => ref,
      "title" => "Counter #{ref}"
    })
  end

  defp portal(view, key), do: view |> element("#body-embeds-portal-body-embed-#{key}") |> render()

  # The content of a portal is in a <template>, which LiveViewTest does not
  # query: the event of its full screen button, as the button sends it.
  defp toggle_full(view, key),
    do:
      view
      |> with_target("#body-embeds")
      |> render_click("full", %{"slot" => "body-embed-#{key}"})

  test "the editor points at its embeds, and they name the toolbar button" do
    {_view, html} = open()
    doc = LazyHTML.from_document(html)

    assert LazyHTML.attribute(LazyHTML.query(doc, "#body"), "data-embeds") == ["#body-embeds"]
    component = LazyHTML.query(doc, "#body-embeds")
    assert LazyHTML.attribute(component, "data-label") == ["Counter"]
    assert LazyHTML.attribute(component, "data-icon") == ["chart"]
    assert LazyHTML.attribute(component, "data-picker") == ["true"]
  end

  test "an embed's slot gets the app's content, in a portal to the slot" do
    {view, _html} = open()
    mount(view, 3, "counter", "42")

    html = portal(view, 3)
    assert html =~ ~s(data-phx-portal="#body-embed-3")
    assert html =~ "counter:42 Counter 42"
    assert html =~ ~s(id="counter-body-embed-3")

    # Another editor's slot is not this one's.
    embeds(view, %{"action" => "mount", "slot" => "other-embed-1", "kind" => "x", "ref" => "1"})
    refute render(view) =~ "other-embed-1"

    embeds(view, %{"action" => "unmount", "slot" => "body-embed-3"})
    refute render(view) =~ "body-embeds-portal-body-embed-3"
  end

  test "full screen: the content goes to the layer over the page, and back" do
    {view, _html} = open()
    mount(view, 3)
    mount(view, 5, "counter", "2")

    toggle_full(view, 3)
    assert portal(view, 3) =~ ~s(data-phx-portal="#body-embeds-full-body")
    assert portal(view, 3) =~ ~s(data-full="true")
    assert portal(view, 5) =~ ~s(data-phx-portal="#body-embed-5")
    refute view |> element("#body-embeds-full") |> render() =~ "hidden"

    view |> element("#body-embeds-full") |> render_keydown(%{"key" => "Escape"})
    assert portal(view, 3) =~ ~s(data-phx-portal="#body-embed-3")
    assert view |> element("#body-embeds-full") |> render() =~ "hidden"

    # An embed that goes while full screen takes the layer with it.
    toggle_full(view, 3)
    embeds(view, %{"action" => "unmount", "slot" => "body-embed-3"})
    assert view |> element("#body-embeds-full") |> render() =~ "hidden"
  end

  test "the picker: opened from the toolbar, the app's options, closed by an insert" do
    {view, _html} = open()
    refute has_element?(view, "#body-embeds-picker")

    embeds(view, %{"action" => "picker"})
    assert has_element?(view, "#body-embeds-picker .kotoba-embed-option", "Counter 9")

    view |> element("#body-embeds-picker button.cancel") |> render_click()
    refute has_element?(view, "#body-embeds-picker")

    embeds(view, %{"action" => "picker"})
    view |> element("#body-embeds-picker .kotoba-embed-option") |> render_click()

    assert_push_event(view, "insert_node", %{id: "body", node: node})

    assert node == %{
             "type" => "embed",
             "version" => 1,
             "kind" => "counter",
             "ref" => "9",
             "title" => "Counter 9"
           }

    assert_push_event(view, "focus", %{id: "body"})
    refute has_element?(view, "#body-embeds-picker")
  end

  test "a read-only editor's embeds are read-only and have no picker" do
    {view, _html} = open("?readonly=true")
    mount(view, 3)
    assert portal(view, 3) =~ "read-only"

    embeds(view, %{"action" => "picker"})
    refute has_element?(view, "#body-embeds-picker")
  end

  test "without a picker, the editor has no Embed button" do
    {_view, html} = open("?picker=false")
    doc = LazyHTML.from_document(html)
    assert LazyHTML.attribute(LazyHTML.query(doc, "#body-embeds"), "data-picker") == ["false"]
  end

  test "an embed renders as its title in the text, the Markdown and the HTML" do
    embed = %{
      "type" => "embed",
      "version" => 1,
      "kind" => "canvas",
      "ref" => "7",
      "title" => "Billing *schema*"
    }

    doc = TestJSON.doc([TestJSON.paragraph([TestJSON.text("Before")]), embed])

    assert Kotoba.Renderer.to_html(doc) |> Phoenix.HTML.safe_to_string() =~
             ~s(<div class="kotoba-embed" data-kind="canvas" data-ref="7">Billing *schema*</div>)

    assert Kotoba.Renderer.to_text(doc) =~ "Billing *schema*"
    assert Kotoba.Renderer.to_markdown(doc) =~ ~S"Billing \*schema\*"
  end

  describe "the app's rendering of an embed" do
    setup do
      embed = %{
        "type" => "embed",
        "version" => 1,
        "kind" => "canvas",
        "ref" => "7",
        "title" => "Model"
      }

      %{doc: TestJSON.doc([TestJSON.paragraph([TestJSON.text("Before")]), embed])}
    end

    defp render(%{kind: "canvas", ref: ref}, :markdown),
      do: "```mermaid\nerDiagram\n  t#{ref}\n```"

    defp render(%{title: title}, :html), do: {:safe, ["<figure>", title, "</figure>"]}
    defp render(_embed, :text), do: nil

    test "the :embed option gives an embed's Markdown and HTML; nil gives the default", %{
      doc: doc
    } do
      assert Kotoba.Renderer.to_markdown(doc, embed: &render/2) ==
               "Before\n\n```mermaid\nerDiagram\n  t7\n```"

      assert Kotoba.Renderer.to_html(doc, embed: &render/2) |> Phoenix.HTML.safe_to_string() ==
               "<p>Before</p><figure>Model</figure>"

      assert Kotoba.Renderer.to_text(doc, embed: &render/2) =~ "Model"
    end

    test "a string for HTML is escaped, as any node's", %{doc: doc} do
      html =
        Kotoba.Renderer.to_html(doc, embed: fn _embed, :html -> "<script>" end)
        |> Phoenix.HTML.safe_to_string()

      assert html =~ "&lt;script&gt;"
    end

    test "kotoba_content takes it, past the cache" do
      {:ok, content} =
        Kotoba.Content.cast(
          TestJSON.envelope([
            %{
              "type" => "embed",
              "version" => 1,
              "kind" => "canvas",
              "ref" => "7",
              "title" => "Model"
            }
          ])
        )

      html =
        Phoenix.LiveViewTest.rendered_to_string(
          Kotoba.Components.kotoba_content(%{
            content: content,
            embed: &render/2,
            __changed__: nil,
            policy: :default,
            nodes: [],
            class: nil,
            rest: %{}
          })
        )

      assert html =~ "<figure>Model</figure>"
    end
  end

  describe "an embed from Markdown" do
    @markdown """
    Before.

    ```mermaid
    %% hakushi kit=schema
    erDiagram
    ```

    ```elixir
    IO.puts(1)
    ```
    """

    defp read(%{language: "mermaid", code: code}),
      do: if(code =~ "kit=schema", do: %{kind: "canvas", ref: "new-1", title: "Schema"})

    defp read(_block), do: nil

    test "a fenced block the app reads becomes an embed; the others stay code" do
      content = Kotoba.Content.from_markdown(@markdown, embed: &read/1)

      assert [
               %{"type" => "paragraph"},
               %{"type" => "embed", "kind" => "canvas", "ref" => "new-1", "title" => "Schema"},
               %{"type" => "code", "language" => "elixir"}
             ] = content.doc["root"]["children"]
    end

    test "without the embeds feature, or a reader, it is code" do
      for opts <- [[], [embed: &read/1, features: Kotoba.Features.all() -- [:embeds]]] do
        content = Kotoba.Content.from_markdown(@markdown, opts)
        refute Enum.any?(content.doc["root"]["children"], &(&1["type"] == "embed"))
      end
    end

    test "the config reads for every import, the editor's paste too" do
      Application.put_env(:kotoba, :embed_from_markdown, &read/1)
      on_exit(fn -> Application.delete_env(:kotoba, :embed_from_markdown) end)

      assert Enum.any?(
               Kotoba.Content.from_markdown(@markdown).doc["root"]["children"],
               &(&1["type"] == "embed")
             )

      assert [_p, %{"type" => "embed"}, _code] =
               Kotoba.MarkdownPaste.nodes(@markdown, %{features: Kotoba.Features.all(), nodes: []})
    end
  end

  test "an embed needs a kind and a ref" do
    assert {:error, ["root.children[0] (embed): ref is required"]} =
             Kotoba.Document.parse(
               TestJSON.envelope([%{"type" => "embed", "version" => 1, "kind" => "canvas"}])
             )

    assert {:ok, _} =
             Kotoba.Document.parse(
               TestJSON.envelope([
                 %{"type" => "embed", "version" => 1, "kind" => "canvas", "ref" => "1"}
               ])
             )
  end
end
