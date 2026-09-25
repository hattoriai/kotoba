defmodule KotobaDev.Nodes.TagTest do
  use ExUnit.Case, async: true

  alias Kotoba.{Document, Renderer}
  alias KotobaDev.Nodes.Tag

  @document %{
    "kotoba" => 1,
    "lexical" => "0.51",
    "root" => %{
      "type" => "root",
      "children" => [
        %{
          "type" => "paragraph",
          "children" => [%{"type" => "dev-tag", "version" => 1, "label" => "Hello"}]
        }
      ]
    }
  }

  test "parses, renders and reads the text of a document with the node" do
    assert {:ok, doc} = Document.parse(@document, nodes: [Tag])
    assert [%Tag{label: "Hello"}] = Document.reduce(doc, [], &collect/2)

    assert doc |> Renderer.to_html() |> Phoenix.HTML.safe_to_string() ==
             ~s(<p><span class="dev-tag">Hello</span></p>)

    assert Renderer.to_text(doc) == "Hello"
    assert Renderer.to_markdown(doc) == "Hello"
    assert {:ok, ^doc} = doc |> Document.to_json() |> Document.parse(nodes: [Tag])
  end

  test "escapes the label" do
    doc = put_in(@document, label_path(), "<b>bold</b>")
    assert {:ok, doc} = Document.parse(doc, nodes: [Tag])
    html = doc |> Renderer.to_html() |> Phoenix.HTML.safe_to_string()
    assert html =~ "&lt;b&gt;bold&lt;/b&gt;"
    refute html =~ "<b>"
  end

  defp collect(%Tag{} = node, acc), do: acc ++ [node]
  defp collect(_node, acc), do: acc

  defp label_path do
    ["root", "children", Access.at(0), "children", Access.at(0), "label"]
  end
end
