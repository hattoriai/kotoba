defmodule Kotoba.RendererPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Kotoba.{Document, DocumentGenerators, Renderer}

  property "to_html/2 returns safe iodata for any document and policy" do
    check all(
            envelope <- DocumentGenerators.envelope(),
            policy <- member_of([:default, :untrusted])
          ) do
      {:ok, doc} = Document.parse(envelope)
      assert {:safe, iodata} = Renderer.to_html(doc, policy: policy)
      assert is_binary(IO.iodata_to_binary(iodata))
      assert is_binary(Renderer.to_markdown(doc, policy: policy))
    end
  end

  property "to_text/2 contains the text of every text node" do
    check all(envelope <- DocumentGenerators.envelope()) do
      {:ok, doc} = Document.parse(envelope)
      text = Renderer.to_text(doc)

      Document.walk(doc, fn
        %Kotoba.Nodes.Text{text: value} -> assert String.contains?(text, value)
        _node -> :ok
      end)
    end
  end

  property "no text or attribute from the document becomes a tag" do
    check all(envelope <- DocumentGenerators.envelope()) do
      {:ok, doc} = Document.parse(envelope)

      doc =
        Document.map(doc, fn
          %Kotoba.Nodes.Text{} = node -> %{node | text: "<script>" <> node.text}
          %Kotoba.Nodes.Mention{} = node -> %{node | id: "\"><script>", label: "<script>"}
          %Kotoba.Nodes.Attachment{} = node -> %{node | name: "\"><script>"}
          node -> node
        end)

      html = doc |> Renderer.to_html() |> Phoenix.HTML.safe_to_string()
      refute html =~ "<script"
    end
  end
end
