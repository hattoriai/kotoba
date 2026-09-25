defmodule Kotoba.Nodes.Tab do
  @moduledoc """
  A tab character (Lexical type `"tab"`).

  Lexical writes a tab node for a Tab key press in a code block, and for
  a tab used to indent text in a paragraph:

      %{"type" => "tab", "detail" => 2, "format" => 0, "mode" => "normal", "style" => "", "text" => "\\t", "version" => 1}

  Kotoba treats it as a text-like inline node and renders its `text` (a
  tab character) as escaped HTML, as plain text and as Markdown.
  """
  use Kotoba.Node, type: "tab", kind: :inline

  field :text, :string, default: "\t", required: true
  field :format, :integer, default: 0
  field :style, :string, default: ""
  field :mode, :string, default: "normal", in: ~w(normal token segmented)
  field :detail, :integer, default: 0

  @impl Kotoba.Node
  def render_html(node, _opts), do: Phoenix.HTML.html_escape(node.text)

  @impl Kotoba.Node
  def render_text(node, _opts), do: node.text

  @impl Kotoba.Node
  def render_markdown(node, _opts), do: node.text
end
