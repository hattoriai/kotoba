defmodule Kotoba.ColorsTest do
  use ExUnit.Case, async: true

  import Kotoba.TestJSON

  alias Kotoba.{Content, Document, Features, Renderer}
  alias Kotoba.Nodes.Text

  defp colored(value, format, style), do: Map.put(text(value, format), "style", style)

  defp html(children) do
    children |> doc() |> Renderer.to_html() |> Phoenix.HTML.safe_to_string()
  end

  test "the palette is the editor's" do
    source = File.read!(Path.expand("../../assets/src/colors.ts", __DIR__))

    [list] =
      Regex.run(~r/export const COLORS = \[(.*?)\] as const;/s, source, capture: :all_but_first)

    assert Regex.scan(~r/"([a-z]+)"/, list, capture: :all_but_first) |> List.flatten() ==
             Text.palette()
  end

  describe "colors/1" do
    test "reads the text color and the highlight color of the palette" do
      style = "color: var(--kotoba-color-red);background-color: var(--kotoba-highlight-green);"

      assert Text.colors(%Text{text: "x", format: 128, style: style}) ==
               %{text: "red", highlight: "green"}

      # White space and the case of the property do not matter; the last
      # declaration of a property wins.
      assert Text.colors(%Text{
               text: "x",
               format: 0,
               style: " COLOR : var(--kotoba-color-gray) ; color:var(--kotoba-color-blue)"
             }) == %{text: "blue", highlight: nil}
    end

    test "the highlight format with no color is the default highlight" do
      assert Text.colors(%Text{text: "x", format: 128, style: ""}) ==
               %{text: nil, highlight: "yellow"}
    end

    test "a background needs the highlight format" do
      style = "background-color: var(--kotoba-highlight-green);"

      assert Text.colors(%Text{text: "x", format: 0, style: style}) == %{
               text: nil,
               highlight: nil
             }
    end

    test "ignores the values that are not in the palette" do
      for style <- [
            "color: red",
            "color: #f00",
            "color: var(--kotoba-color-nope)",
            "color: var(--kotoba-highlight-red)",
            "color: var(--kotoba-color-red) !important",
            "color: var(--kotoba-color-red)\" onclick=\"x",
            "color: var(--kotoba-color-RED)",
            "color: var(--other-color-red)",
            "color: expression(alert(1))",
            "background: var(--kotoba-highlight-red)",
            "background-color: var(--kotoba-color-red)",
            "",
            ";;:"
          ] do
        assert Text.colors(%Text{text: "x", format: 128, style: style}) ==
                 %{text: nil, highlight: "yellow"},
               "style #{inspect(style)}"
      end

      assert Text.colors(%Text{text: "x", format: 0, style: nil}) == %{text: nil, highlight: nil}
    end
  end

  describe "HTML" do
    test "a text color is a span with its class, a highlight color a class of the mark" do
      style = "color: var(--kotoba-color-red);background-color: var(--kotoba-highlight-green);"

      assert html([paragraph([colored("t", 1 + 128, style)])]) ==
               ~s(<p><span class="kotoba-color-red"><strong>) <>
                 ~s(<mark class="kotoba-highlight-green">t</mark></strong></span></p>)
    end

    test "the default highlight is a mark with no class, as before the palette" do
      assert html([paragraph([text("t", 128)])]) == "<p><mark>t</mark></p>"

      assert html([
               paragraph([colored("t", 128, "background-color: var(--kotoba-highlight-yellow);")])
             ]) == "<p><mark>t</mark></p>"
    end

    test "a text color alone, and every color of the palette" do
      for name <- Text.palette() do
        assert html([paragraph([colored("t", 0, "color: var(--kotoba-color-#{name});")])]) ==
                 ~s(<p><span class="kotoba-color-#{name}">t</span></p>)
      end
    end

    test "a style that is not a color of the palette renders nothing" do
      input = [
        paragraph([
          colored("a", 0, "color: red"),
          colored("b", 0, "background-color: var(--kotoba-highlight-green);"),
          colored("c", 128, "color: url(javascript:alert(1))")
        ])
      ]

      assert html(input) == "<p>ab<mark>c</mark></p>"
    end

    test "text and Markdown have no colors" do
      doc = doc([paragraph([colored("t", 128, "color: var(--kotoba-color-red);")])])
      assert Renderer.to_text(doc) == "t"
      assert Renderer.to_markdown(doc) == "t"
    end
  end

  test "the colors survive a cast, a store and a load" do
    style = "color: var(--kotoba-color-blue);background-color: var(--kotoba-highlight-purple);"

    expected =
      ~s(<p><span class="kotoba-color-blue"><mark class="kotoba-highlight-purple">t</mark></span></p>)

    {:ok, content} = Content.cast(envelope([paragraph([colored("t", 128, style)])]))
    assert content.html == expected

    {:ok, stored} = Content.dump(content)
    # With no cached HTML, the load renders it again.
    {:ok, loaded} = Content.load(Map.delete(stored, "html"))
    assert loaded.html == expected

    {:ok, document} = Document.parse(loaded.doc)
    [%{children: [run]}] = document.root.children
    assert run.style == style
  end

  test "a text color is the highlight feature" do
    input = doc([paragraph([colored("t", 0, "color: var(--kotoba-color-red);")])])
    assert Features.used(input) == [:highlight]
    assert Features.check(input, [:bold]) == {:error, [:highlight]}

    # A style that is not a color is not a feature.
    assert Features.used(doc([paragraph([colored("t", 0, "color: red")])])) == []
  end
end
