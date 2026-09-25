defmodule Kotoba.Nodes.Code do
  @moduledoc """
  A code block (Lexical type `"code"`).

  `language` is the language of the code, or `nil`. The children are
  `Kotoba.Nodes.CodeHighlight`, `Kotoba.Nodes.Text` and
  `Kotoba.Nodes.LineBreak` nodes.
  """
  use Kotoba.Node, type: "code", kind: :block, element: true

  field :language, :string, omit_nil: true
end
