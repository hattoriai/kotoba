defmodule Kotoba.Nodes.Root do
  @moduledoc """
  The root node of a document (Lexical type `"root"`).

  A document has one root node, at the top. Its children are block nodes.
  """
  use Kotoba.Node, type: "root", kind: :block, element: true

  alias Kotoba.Renderer

  @impl Kotoba.Node
  def render_html(node, opts), do: Renderer.html_children(node, opts)

  @impl Kotoba.Node
  def render_text(node, opts), do: Renderer.text_children(node, opts)

  @impl Kotoba.Node
  def render_markdown(node, opts), do: Renderer.markdown_children(node, opts)
end
