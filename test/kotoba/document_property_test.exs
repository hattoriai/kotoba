defmodule Kotoba.DocumentPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Kotoba.{Document, DocumentGenerators}

  property "to_json/1 writes the JSON that parse/2 read" do
    check all(envelope <- DocumentGenerators.envelope()) do
      assert {:ok, doc} = Document.parse(envelope)
      assert Document.to_json(doc) == envelope
    end
  end

  property "a document survives a JSON encode and parse" do
    check all(envelope <- DocumentGenerators.envelope()) do
      {:ok, doc} = Document.parse(envelope)
      assert {:ok, ^doc} = doc |> Document.to_json() |> JSON.encode!() |> Document.parse()
    end
  end

  property "map/2 with the identity function gives the same document" do
    check all(envelope <- DocumentGenerators.envelope()) do
      {:ok, doc} = Document.parse(envelope)
      assert Document.map(doc, & &1) == doc
    end
  end

  property "text/1 contains the text of every text node" do
    check all(envelope <- DocumentGenerators.envelope()) do
      {:ok, doc} = Document.parse(envelope)
      text = Document.text(doc)

      Document.walk(doc, fn
        %Kotoba.Nodes.Text{text: value} -> assert String.contains?(text, value)
        _node -> :ok
      end)
    end
  end
end
