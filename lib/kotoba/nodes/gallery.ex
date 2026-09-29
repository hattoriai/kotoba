defmodule Kotoba.Nodes.Gallery do
  @moduledoc """
  A gallery of images (Lexical type `"gallery"`): attachments shown
  together, in a grid.

  A gallery is valid only under the root, and holds only
  `Kotoba.Nodes.Attachment` nodes, in their order. The editor makes a
  gallery of the images uploaded together, and of the images that the
  person groups; it makes one image of a gallery with one image.

  In HTML, a gallery is a `div.kotoba-gallery` with the `figure` of each
  attachment. With the `:untrusted` policy, it is a `p` with the names of
  the files. Its text is the names, one a line, and its Markdown the
  images, one a line.
  """
  use Kotoba.Node, type: "gallery", kind: :block, element: true

  alias Kotoba.Nodes.Attachment
  alias Kotoba.Renderer

  @impl Kotoba.Node
  def render_html(node, opts) do
    if Renderer.policy(opts).attachments do
      Renderer.tag("div", [class: "kotoba-gallery"], Renderer.html_children(node, opts))
    else
      Renderer.tag("p", [], Enum.join(names(node), ", "))
    end
  end

  # The attachments of a gallery are not in the root, so the renderer would
  # join them as inline nodes: each one gets its line.
  @impl Kotoba.Node
  def render_text(node, opts), do: node |> Renderer.text_each(opts) |> lines()

  @impl Kotoba.Node
  def render_markdown(node, opts), do: node |> Renderer.markdown_each(opts) |> lines()

  defp lines(rendered) do
    rendered
    |> Enum.map(&elem(&1, 1))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp names(node), do: for(%Attachment{name: name} <- node.children, do: name)
end
