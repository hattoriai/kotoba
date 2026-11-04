defmodule KotobaTest.Overrides.Links do
  @moduledoc false
  # A link to a page of the app (`/pages/<id>`) goes to where the page is
  # now (the `:pages` render option), or is only its text when the page is
  # gone. Other links render as Kotoba renders them. A link with the state
  # "target" opens there.
  use Kotoba.Node.Override, of: Kotoba.Nodes.Link

  alias Kotoba.Node.Override
  alias Kotoba.Nodes.Link

  @impl Override
  def render_html(%{url: "/pages/" <> id} = node, opts) do
    case Map.fetch(Keyword.get(opts, :pages, %{}), id) do
      {:ok, url} -> Link.render_html(%{node | url: url}, opts)
      :error -> Kotoba.Renderer.html_children(node, opts)
    end
  end

  def render_html(node, opts) do
    case Override.state(node, "target") do
      nil ->
        Link.render_html(node, opts)

      target ->
        Kotoba.Renderer.tag(
          "a",
          [href: node.url, target: target, rel: "noopener"],
          Kotoba.Renderer.html_children(node, opts)
        )
    end
  end

  @impl Override
  def render_markdown(node, opts), do: "[link] " <> Kotoba.Renderer.text_children(node, opts)
end
