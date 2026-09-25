defmodule Kotoba.Nodes.Code do
  @moduledoc """
  A code block (Lexical type `"code"`).

  `language` is the language of the code, or `nil`. The children are
  `Kotoba.Nodes.CodeHighlight`, `Kotoba.Nodes.Text` and
  `Kotoba.Nodes.LineBreak` nodes.
  """
  use Kotoba.Node, type: "code", kind: :block, element: true

  alias Kotoba.Renderer

  field :language, :string, omit_nil: true

  @impl Kotoba.Node
  def render_html(node, opts) do
    class = if language?(node.language), do: "language-" <> node.language
    code = Renderer.tag("code", [class: class], Renderer.text_children(node, opts))
    Renderer.tag("pre", [], code)
  end

  @impl Kotoba.Node
  def render_text(node, opts), do: Renderer.text_children(node, opts)

  @impl Kotoba.Node
  def render_markdown(node, opts) do
    code = Renderer.text_children(node, opts)
    fence = String.duplicate("`", max(3, Kotoba.Markdown.longest_run(code, "`") + 1))
    language = if language?(node.language), do: node.language, else: ""
    fence <> language <> "\n" <> code <> "\n" <> fence
  end

  # A language goes into a class name, so it has only safe characters.
  defp language?(language) when is_binary(language),
    do: Regex.match?(~r/\A[a-zA-Z0-9_+#.\-]+\z/, language)

  defp language?(_language), do: false
end
