defmodule Kotoba.Nodes.AutoLink do
  @moduledoc """
  A link that the editor made from a URL in the text (Lexical type
  `"autolink"`). Its children are inline nodes.

  `is_unlinked` is `true` when the writer removed the link. `rel`, `target`
  and `title` can be `nil`.
  """
  use Kotoba.Node, type: "autolink", kind: :inline, element: true

  field :url, :string, required: true
  field :rel, :string
  field :target, :string
  field :title, :string
  field :is_unlinked, :boolean, key: "isUnlinked", default: false
end
