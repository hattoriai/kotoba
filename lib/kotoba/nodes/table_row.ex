defmodule Kotoba.Nodes.TableRow do
  @moduledoc """
  A row of a table (Lexical type `"tablerow"`).

  The children are `Kotoba.Nodes.TableCell` nodes, and a row is valid only
  in a `Kotoba.Nodes.Table`. The editor's `height` key stays in `extra`.
  """
  use Kotoba.Node, type: "tablerow", kind: :block, element: true

  alias Kotoba.Renderer

  @impl Kotoba.Node
  def render_html(node, opts), do: Renderer.tag("tr", [], Renderer.html_children(node, opts))

  # The cells, separated by a tab.
  @impl Kotoba.Node
  def render_text(node, opts), do: cells(node, opts, &Renderer.text_each/2)

  # The cells, separated by a tab, for `Kotoba.Nodes.Table` to lay out.
  @impl Kotoba.Node
  def render_markdown(node, opts), do: cells(node, opts, &Renderer.markdown_each/2)

  defp cells(node, opts, each) do
    node |> each.(opts) |> Enum.map_join("\t", &elem(&1, 1))
  end
end
