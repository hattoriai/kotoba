defmodule KotobaDev.Nodes.Callout do
  @moduledoc """
  The `dev-callout` node, kind `:block`: a callout box of inline content.

  It is the server half of the example extension,
  `dev/assets/js/kotoba/nodes/callout.js`, which adds the node, a command
  that toggles a callout, a toolbar button and the `!!! ` Markdown shortcut.
  See the Extensions guide.
  """
  use Kotoba.Node, type: "dev-callout", kind: :block, element: true

  alias Kotoba.Renderer

  @impl Kotoba.Node
  def render_html(node, opts),
    do: Renderer.tag("aside", [class: "dev-callout"], Renderer.html_children(node, opts))

  @impl Kotoba.Node
  def render_text(node, opts), do: Renderer.text_children(node, opts)

  @impl Kotoba.Node
  def render_markdown(node, opts), do: "> **Note:** " <> Renderer.markdown_children(node, opts)
end
