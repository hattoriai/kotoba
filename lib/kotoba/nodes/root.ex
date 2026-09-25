defmodule Kotoba.Nodes.Root do
  @moduledoc """
  The root node of a document (Lexical type `"root"`).

  A document has one root node, at the top. Its children are block nodes.
  """
  use Kotoba.Node, type: "root", kind: :block, element: true
end
