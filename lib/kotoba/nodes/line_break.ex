defmodule Kotoba.Nodes.LineBreak do
  @moduledoc """
  A line break in a block (Lexical type `"linebreak"`).
  """
  use Kotoba.Node, type: "linebreak", kind: :inline

  alias Kotoba.Renderer

  @impl Kotoba.Node
  def render_html(_node, _opts), do: Renderer.tag("br", [], :void)

  @impl Kotoba.Node
  def render_text(_node, _opts), do: "\n"

  @impl Kotoba.Node
  def render_markdown(_node, _opts), do: "  \n"
end
