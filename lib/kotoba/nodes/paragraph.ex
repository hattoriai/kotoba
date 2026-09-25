defmodule Kotoba.Nodes.Paragraph do
  @moduledoc """
  A paragraph (Lexical type `"paragraph"`).

  `text_format` and `text_style` are the format and the style that Lexical
  gives to new text in the paragraph.
  """
  use Kotoba.Node, type: "paragraph", kind: :block, element: true

  field :text_format, :integer, key: "textFormat", default: 0
  field :text_style, :string, key: "textStyle", default: ""
end
