defmodule KotobaDev.Nodes.Tag do
  @moduledoc """
  The `dev-tag` node, kind `:inline`.

  Its editor half is `dev/assets/js/kotoba/nodes/tag.js`,
  whose `exportJSON()` writes the JSON keys of the fields below. A field
  with more than one word takes a camelCase key, for example
  `field :ref_id, :string, key: "refId"`, and the JavaScript uses the
  same key.
  """
  use Kotoba.Node, type: "dev-tag", kind: :inline

  alias Kotoba.Renderer

  field :label, :string, required: true

  @impl Kotoba.Node
  def render_html(node, _opts) do
    Renderer.tag("span", [class: "dev-tag"], node.label)
  end

  @impl Kotoba.Node
  def render_text(node, _opts), do: node.label

  @impl Kotoba.Node
  def render_markdown(node, _opts), do: Renderer.escape_markdown(node.label)
end
