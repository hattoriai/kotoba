defmodule KotobaDev.Nodes.Spoiler do
  @moduledoc """
  The `dev-spoiler` node, kind `:inline`: a text mark of an extension, an
  inline element over the text. The editor half is
  `dev/assets/js/kotoba/nodes/points.js`, which toggles it with the
  extension API's `inline`.
  """
  use Kotoba.Node, type: "dev-spoiler", kind: :inline, element: true

  alias Kotoba.Renderer

  @impl Kotoba.Node
  def render_html(node, opts),
    do: Renderer.tag("span", [class: "dev-spoiler"], Renderer.html_children(node, opts))

  @impl Kotoba.Node
  def render_text(node, opts), do: Renderer.text_children(node, opts)

  @impl Kotoba.Node
  def render_markdown(node, opts), do: "||" <> Renderer.markdown_children(node, opts) <> "||"
end
