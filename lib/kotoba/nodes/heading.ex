defmodule Kotoba.Nodes.Heading do
  @moduledoc """
  A heading (Lexical type `"heading"`). `tag` is `"h1"` to `"h6"`.
  """
  use Kotoba.Node, type: "heading", kind: :block, element: true

  field :tag, :string, required: true, in: ~w(h1 h2 h3 h4 h5 h6)
end
