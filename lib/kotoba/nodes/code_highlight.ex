defmodule Kotoba.Nodes.CodeHighlight do
  @moduledoc """
  A token of text in a code block (Lexical type `"code-highlight"`).

  `highlight_type` is the token type from the highlighter, for example
  `"keyword"`, or `nil`. The other fields are the same as in
  `Kotoba.Nodes.Text`.
  """
  use Kotoba.Node, type: "code-highlight", kind: :inline

  field :text, :string, required: true
  field :highlight_type, :string, key: "highlightType", omit_nil: true
  field :format, :integer, default: 0
  field :style, :string, default: ""
  field :mode, :string, default: "normal", in: ~w(normal token segmented)
  field :detail, :integer, default: 0

  @impl Kotoba.Node
  def render_html(node, _opts), do: Phoenix.HTML.html_escape(node.text)

  @impl Kotoba.Node
  def render_text(node, _opts), do: node.text
end
