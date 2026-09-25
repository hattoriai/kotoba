defmodule Kotoba.Nodes.ListItem do
  @moduledoc """
  An item of a list (Lexical type `"listitem"`).

  `value` is the number of the item. `checked` is `true` or `false` in a
  check list and `nil` in other lists.
  """
  use Kotoba.Node, type: "listitem", kind: :block, element: true

  field :value, :integer, default: 1
  field :checked, :boolean, omit_nil: true
end
