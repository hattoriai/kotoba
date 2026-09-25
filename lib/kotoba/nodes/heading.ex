defmodule Kotoba.Nodes.Heading do
  @moduledoc """
  A heading (Lexical type `"heading"`). `tag` is `"h1"` to `"h6"`.
  """
  use Kotoba.Node, type: "heading", kind: :block, element: true

  alias Kotoba.Renderer

  field :tag, :string, required: true, in: ~w(h1 h2 h3 h4 h5 h6)

  @impl Kotoba.Node
  def render_html(node, opts),
    do: Renderer.tag(html_tag(node.tag), [], Renderer.html_children(node, opts))

  @impl Kotoba.Node
  def render_text(node, opts), do: Renderer.text_children(node, opts)

  @impl Kotoba.Node
  def render_markdown(node, opts) do
    "h" <> level = node.tag
    text = node |> Renderer.markdown_children(opts) |> String.replace(~r/ *\n/, " ")
    String.duplicate("#", String.to_integer(level)) <> " " <> text
  end

  defp html_tag(tag) when tag in ~w(h5 h6), do: "h4"
  defp html_tag(tag), do: tag
end
