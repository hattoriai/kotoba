defmodule Kotoba.Nodes.List do
  @moduledoc """
  A list (Lexical type `"list"`).

  `list_type` is `"bullet"`, `"number"` or `"check"`. `start` is the number
  of the first item. `tag` is `"ul"` or `"ol"`. The children are
  `Kotoba.Nodes.ListItem` nodes.
  """
  use Kotoba.Node, type: "list", kind: :block, element: true

  alias Kotoba.Nodes.ListItem
  alias Kotoba.Renderer

  field :list_type, :string, key: "listType", required: true, in: ~w(bullet number check)
  field :start, :integer, default: 1
  field :tag, :string, required: true, in: ~w(ul ol)

  @impl Kotoba.Node
  def render_html(node, opts) do
    {tag, attrs} =
      case node.list_type do
        "number" -> {"ol", [start: if(node.start != 1, do: node.start)]}
        "bullet" -> {"ul", []}
        "check" -> {"ul", [class: "kotoba-check"]}
      end

    Renderer.tag(tag, attrs, Renderer.html_children(node, opts))
  end

  @impl Kotoba.Node
  def render_text(node, opts), do: Renderer.text_children(node, opts)

  @impl Kotoba.Node
  def render_markdown(node, opts) do
    node
    |> Renderer.markdown_each(opts)
    |> Enum.filter(fn {item, _markdown} -> match?(%ListItem{}, item) end)
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {{item, markdown}, index} -> item(node, item, index, markdown) end)
  end

  defp item(node, item, index, markdown) do
    marker =
      case node.list_type do
        "number" -> "#{node.start + index}. "
        _other -> "- "
      end

    indent = String.duplicate(" ", String.length(marker))

    if ListItem.nested_only?(item) do
      indent(markdown, indent, indent)
    else
      indent(markdown, marker <> check(node, item), indent)
    end
  end

  defp check(%{list_type: "check"}, %{checked: true}), do: "[x] "
  defp check(%{list_type: "check"}, _item), do: "[ ] "
  defp check(_node, _item), do: ""

  defp indent(markdown, first, rest) do
    [line | lines] = String.split(markdown, "\n")
    Enum.join([first <> line | Enum.map(lines, &if(&1 == "", do: "", else: rest <> &1))], "\n")
  end
end
