defmodule KotobaTest.Nodes.Pointer do
  @moduledoc """
  An app-defined node for the tests (type `"test-pointer"`): a decorator
  that points at a URL, with a label.

  The target goes through `Kotoba.Sanitizer.link_url/2`. A target that the
  sanitizer refuses, or a policy with no links, renders the label as text.
  """
  use Kotoba.Node, type: "test-pointer", kind: :decorator

  alias Kotoba.{Renderer, Sanitizer}

  field :target, :string, required: true
  field :label, :string, required: true

  @impl Kotoba.Node
  def render_html(node, opts) do
    case href(node, opts) do
      nil -> node.label
      href -> Renderer.tag("a", [class: "test-pointer", href: href], node.label)
    end
  end

  @impl Kotoba.Node
  def render_text(node, _opts), do: node.label

  @impl Kotoba.Node
  def render_markdown(node, opts) do
    label = Renderer.escape_markdown(node.label)

    case href(node, opts) do
      nil -> label
      href -> "[" <> label <> "](" <> Kotoba.Markdown.url(href) <> ")"
    end
  end

  defp href(node, opts) do
    if Renderer.policy(opts).links, do: Sanitizer.link_url(node.target, opts)
  end
end
