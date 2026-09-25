defmodule Kotoba.Nodes.Quote do
  @moduledoc """
  A block quote (Lexical type `"quote"`).
  """
  use Kotoba.Node, type: "quote", kind: :block, element: true

  alias Kotoba.Renderer

  @impl Kotoba.Node
  def render_html(node, opts),
    do: Renderer.tag("blockquote", [], Renderer.html_children(node, opts))

  @impl Kotoba.Node
  def render_text(node, opts), do: Renderer.text_children(node, opts)

  @impl Kotoba.Node
  def render_markdown(node, opts) do
    node
    |> Renderer.markdown_children(opts)
    |> String.split("\n")
    |> Enum.map_join("\n", &if(&1 == "", do: ">", else: "> " <> &1))
  end
end
