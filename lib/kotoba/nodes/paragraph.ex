defmodule Kotoba.Nodes.Paragraph do
  @moduledoc """
  A paragraph (Lexical type `"paragraph"`).

  `text_format` and `text_style` are the format and the style that Lexical
  gives to new text in the paragraph.
  """
  use Kotoba.Node, type: "paragraph", kind: :block, element: true

  alias Kotoba.Renderer

  field :text_format, :integer, key: "textFormat", default: 0
  field :text_style, :string, key: "textStyle", default: ""

  @impl Kotoba.Node
  def render_html(node, opts), do: Renderer.tag("p", [], Renderer.html_children(node, opts))

  @impl Kotoba.Node
  def render_text(node, opts), do: Renderer.text_children(node, opts)

  @impl Kotoba.Node
  def render_markdown(node, opts), do: Renderer.markdown_children(node, opts)
end
