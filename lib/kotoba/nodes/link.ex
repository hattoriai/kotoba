defmodule Kotoba.Nodes.Link do
  @moduledoc """
  A link (Lexical type `"link"`). Its children are inline nodes.

  `rel`, `target` and `title` can be `nil`.
  """
  use Kotoba.Node, type: "link", kind: :inline, element: true

  field :url, :string, required: true
  field :rel, :string
  field :target, :string
  field :title, :string
end
