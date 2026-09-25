defmodule Kotoba.Nodes.Mention do
  @moduledoc """
  A mention of a thing in the app (type `"mention"`), for example a person.
  The JSON keys are `kind`, `id` and `label`.

    * `kind` - the prompt kind that made the mention, for example `"people"`.
    * `id` - the ID of the thing, as a string.
    * `label` - the text that the reader sees.
  """
  use Kotoba.Node, type: "mention", kind: :decorator

  alias Kotoba.Renderer

  field :kind, :string, required: true
  field :id, :string, required: true
  field :label, :string, required: true

  @impl Kotoba.Node
  def render_html(node, _opts) do
    Renderer.tag(
      "span",
      [class: "kotoba-mention", "data-kind": node.kind, "data-id": node.id],
      node.label
    )
  end

  @impl Kotoba.Node
  def render_text(node, _opts), do: node.label

  @impl Kotoba.Node
  def render_markdown(node, _opts), do: Kotoba.Markdown.escape(node.label)
end
