defmodule Kotoba.Nodes.HorizontalRule do
  @moduledoc """
  A horizontal rule (Lexical type `"horizontalrule"`).
  """
  use Kotoba.Node, type: "horizontalrule", kind: :decorator

  alias Kotoba.Renderer

  @impl Kotoba.Node
  def render_html(_node, _opts), do: Renderer.tag("hr", [], :void)

  @impl Kotoba.Node
  def render_text(_node, _opts), do: ""

  @impl Kotoba.Node
  def render_markdown(_node, _opts), do: "---"
end
