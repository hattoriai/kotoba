defmodule Kotoba.Node.OverrideTest do
  # async: false because some tests set `config :kotoba, overrides:`.
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Kotoba.{Components, Content, Renderer}
  alias Kotoba.Node.Override
  alias KotobaTest.Overrides.Links

  setup do
    previous = Application.fetch_env(:kotoba, :overrides)

    on_exit(fn ->
      case previous do
        {:ok, overrides} -> Application.put_env(:kotoba, :overrides, overrides)
        :error -> Application.delete_env(:kotoba, :overrides)
      end
    end)

    Application.delete_env(:kotoba, :overrides)
    :ok
  end

  defp doc(markdown) do
    {:ok, doc} =
      markdown |> Content.from_markdown() |> Map.fetch!(:doc) |> Kotoba.Document.parse()

    doc
  end

  defp html(doc, opts), do: doc |> Renderer.to_html(opts) |> Phoenix.HTML.safe_to_string()

  test "an override renders the node; the callbacks it does not define render as the node" do
    doc = doc("See [Kotoba](/pages/5) and [Lexical](https://lexical.dev)")
    opts = [overrides: [Links], pages: %{"5" => "/kotoba"}]

    assert html(doc, opts) ==
             ~s(<p>See <a href="/kotoba" rel="noopener nofollow">Kotoba</a> and <a href="https://lexical.dev" rel="noopener nofollow">Lexical</a></p>)

    # The page is gone: only its text.
    assert html(doc, overrides: [Links]) ==
             ~s(<p>See Kotoba and <a href="https://lexical.dev" rel="noopener nofollow">Lexical</a></p>)

    # Without the override, as Kotoba renders it.
    assert html(doc, []) =~ ~s(href="/pages/5")

    assert Renderer.to_markdown(doc, opts) == "See [link] Kotoba and [link] Lexical"
    # render_text is not defined: the link's own text.
    assert Renderer.to_text(doc, opts) == "See Kotoba and Lexical"
  end

  test "the configured overrides apply to the HTML that a content keeps; the caller's replace them" do
    markdown = "See [Kotoba](/pages/5)"
    assert Content.from_markdown(markdown).html =~ ~s(href="/pages/5")

    Application.put_env(:kotoba, :overrides, [Links])
    content = Content.from_markdown(markdown)
    assert content.html == "<p>See Kotoba</p>"

    assert Content.rerender(content, pages: %{"5" => "/kotoba"}).html ==
             ~s(<p>See <a href="/kotoba" rel="noopener nofollow">Kotoba</a></p>)
  end

  test "kotoba_content renders again with its overrides and options, else uses the kept HTML" do
    content = Content.from_markdown("See [Kotoba](/pages/5)")

    assert render_component(&Components.kotoba_content/1, content: content) =~ ~s(href="/pages/5")

    html =
      render_component(&Components.kotoba_content/1,
        content: content,
        overrides: [Links],
        opts: [pages: %{"5" => "/kotoba"}]
      )

    assert html =~ ~s(<a href="/kotoba" rel="noopener nofollow">Kotoba</a>)
  end

  test "an extension's state on a node is kept, and an override reads it" do
    doc =
      doc("[Kotoba](https://hattori.ai/kotoba)")
      |> Kotoba.Document.to_json()
      |> put_in(["root", "children", Access.at(0), "children", Access.at(0), "$"], %{
        "target" => "_blank"
      })

    {:ok, parsed} = Kotoba.Document.parse(doc)

    # Kept: the JSON goes back as it came.
    assert Kotoba.Document.to_json(parsed) == doc
    [%{children: [link]}] = parsed.root.children
    assert Override.state(link, "target") == "_blank"
    assert Override.state(link, "missing", :none) == :none

    assert html(parsed, overrides: [Links]) ==
             ~s(<p><a href="https://hattori.ai/kotoba" target="_blank" rel="noopener">Kotoba</a></p>)
  end

  test "a module that is not an override is refused" do
    assert_raise ArgumentError, ~r/is not a Kotoba.Node.Override/, fn ->
      Override.registry([Kotoba.Nodes.Link])
    end

    assert_raise ArgumentError, ~r/is not a Kotoba.Node.Override/, fn ->
      Renderer.to_html(doc("text"), overrides: [String])
    end
  end
end
