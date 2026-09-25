defmodule Kotoba.Nodes.ListItem do
  @moduledoc """
  An item of a list (Lexical type `"listitem"`).

  `value` is the number of the item. `checked` is `true` or `false` in a
  check list and `nil` in other lists.
  """
  use Kotoba.Node, type: "listitem", kind: :block, element: true

  alias Kotoba.Renderer

  field :value, :integer, default: 1
  field :checked, :boolean, omit_nil: true

  @impl Kotoba.Node
  def render_html(node, opts) do
    class =
      case {opts[:parent], node.checked} do
        {%Kotoba.Nodes.List{list_type: "check"}, true} ->
          "kotoba-checked"

        {%Kotoba.Nodes.List{list_type: "check"}, false} ->
          "kotoba-unchecked"

        {%Kotoba.Nodes.List{list_type: "check"}, nil} ->
          unless nested_only?(node), do: "kotoba-unchecked"

        _other ->
          nil
      end

    Renderer.tag("li", [class: class], Renderer.html_children(node, opts))
  end

  @impl Kotoba.Node
  def render_text(node, opts), do: Renderer.text_children(node, opts)

  @impl Kotoba.Node
  def render_markdown(node, opts), do: Renderer.markdown_children(node, opts, "\n")

  @doc """
  Returns `true` when the item holds only a nested list. Lexical puts a
  nested list in an item of its own.
  """
  @spec nested_only?(t()) :: boolean()
  def nested_only?(%__MODULE__{children: children}),
    do: children != [] and Enum.all?(children, &match?(%Kotoba.Nodes.List{}, &1))
end
