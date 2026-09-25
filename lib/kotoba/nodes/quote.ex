defmodule Kotoba.Nodes.Quote do
  @moduledoc """
  A block quote (Lexical type `"quote"`).
  """
  use Kotoba.Node, type: "quote", kind: :block, element: true
end
