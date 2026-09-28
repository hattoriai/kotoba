defmodule KotobaDev.Nodes.CalloutTest do
  use ExUnit.Case, async: true

  import Kotoba.TestJSON

  alias Kotoba.{Document, Renderer}
  alias KotobaDev.Nodes.Callout

  test "parses, renders and reads the text of a document with the node" do
    envelope = envelope([element("dev-callout", [text("Mind the gap", 1)])])

    assert {:ok, doc} = Document.parse(envelope, nodes: [Callout])
    assert [%Callout{children: [%Kotoba.Nodes.Text{}]}] = doc.root.children

    assert doc |> Renderer.to_html() |> Phoenix.HTML.safe_to_string() ==
             ~s(<aside class="dev-callout"><strong>Mind the gap</strong></aside>)

    assert Renderer.to_text(doc) == "Mind the gap"
    assert Renderer.to_markdown(doc) == "> **Note:** **Mind the gap**"
    assert Document.to_json(doc) == envelope
  end
end
