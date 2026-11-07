defmodule KotobaDev.Overrides.Links do
  @moduledoc """
  Links as /points renders them (`Kotoba.Node.Override`): a link to a page
  of the dev pages (`/pages/<id>`) goes to its path now (`/docs/<slug>`),
  or is only its text when there is no such page; a link with the state
  `target` (the extension's "Open in a new tab") opens there.
  """
  use Kotoba.Node.Override, of: Kotoba.Nodes.Link

  alias Kotoba.Node.Override
  alias Kotoba.Nodes.Link
  alias Kotoba.Renderer

  @pages [
    {"5", "Kotoba", "kotoba"},
    {"6", "Issho", "issho"},
    {"7", "Storehouse", "storehouse"},
    {"8", "Kotoba guides", "kotoba-guides"}
  ]

  @doc "The dev pages: `{id, title, slug}`."
  def pages, do: @pages

  @doc "The path of a dev page now, from its id, or nil."
  def page_path(id) do
    Enum.find_value(@pages, fn {page, _title, slug} -> if page == id, do: "/docs/" <> slug end)
  end

  @impl Override
  def render_html(%{url: "/pages/" <> id} = node, opts) do
    case page_path(id) do
      nil -> Renderer.html_children(node, opts)
      path -> Link.render_html(%{node | url: path}, opts)
    end
  end

  def render_html(node, opts) do
    case Override.state(node, "target") do
      "_blank" ->
        Renderer.tag(
          "a",
          [href: node.url, target: "_blank", rel: "noopener noreferrer"],
          Renderer.html_children(node, opts)
        )

      _none ->
        Link.render_html(node, opts)
    end
  end
end
