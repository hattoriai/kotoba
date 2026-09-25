defmodule Kotoba.Nodes.List do
  @moduledoc """
  A list (Lexical type `"list"`).

  `list_type` is `"bullet"`, `"number"` or `"check"`. `start` is the number
  of the first item. `tag` is `"ul"` or `"ol"`. The children are
  `Kotoba.Nodes.ListItem` nodes.
  """
  use Kotoba.Node, type: "list", kind: :block, element: true

  field :list_type, :string, key: "listType", required: true, in: ~w(bullet number check)
  field :start, :integer, default: 1
  field :tag, :string, required: true, in: ~w(ul ol)
end
