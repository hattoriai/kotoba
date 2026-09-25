defmodule Kotoba.Nodes.LineBreak do
  @moduledoc """
  A line break in a block (Lexical type `"linebreak"`).
  """
  use Kotoba.Node, type: "linebreak", kind: :inline
end
