defmodule Kotoba.Nodes.Attachment do
  @moduledoc """
  A file in the document (type `"attachment"`), for example an image.

  The JSON keys are camelCase, as in Lexical: `key`, `url`, `name`,
  `contentType`, `bytes`, `width` and `height`.

  In HTML, an attachment is a `figure` with the class `kotoba-attachment`.
  An image has an `img` and a `figcaption` with the name. Another file has a
  `figcaption` with a download link. With the `:untrusted` policy, only the
  name is rendered.

    * `key` - the storage key of the file.
    * `url` - the URL of the file.
    * `name` - the file name.
    * `content_type` - the media type, for example `"image/png"`.
    * `bytes` - the size of the file.
    * `width` and `height` - the size of an image in pixels, or `nil`.
  """
  use Kotoba.Node, type: "attachment", kind: :decorator

  alias Kotoba.{Markdown, Renderer, Sanitizer}

  field :key, :string, required: true
  field :url, :string, required: true
  field :name, :string, required: true
  field :content_type, :string, key: "contentType", required: true
  field :bytes, :integer, required: true
  field :width, :integer, omit_nil: true
  field :height, :integer, omit_nil: true

  @doc """
  Returns `true` when the attachment is an image.

  ## Examples

      iex> Kotoba.Nodes.Attachment.image?(%Kotoba.Nodes.Attachment{content_type: "image/png"})
      true

  """
  @spec image?(t()) :: boolean()
  def image?(%__MODULE__{content_type: "image/" <> _subtype}), do: true
  def image?(%__MODULE__{}), do: false

  @impl Kotoba.Node
  def render_html(node, opts) do
    if Renderer.policy(opts).attachments do
      url = Sanitizer.link_url(node.url, opts)
      Renderer.tag("figure", [class: "kotoba-attachment"], figure(node, url))
    else
      Phoenix.HTML.html_escape(node.name)
    end
  end

  defp figure(node, url) do
    caption =
      if image?(node) do
        Renderer.tag("figcaption", [], node.name)
      else
        link = Renderer.tag("a", [href: url, download: true, rel: "noopener nofollow"], node.name)
        Renderer.tag("figcaption", [], link)
      end

    image =
      if image?(node),
        do:
          Renderer.tag(
            "img",
            [src: url, alt: node.name, width: node.width, height: node.height],
            :void
          ),
        else: {:safe, ""}

    {:safe, [elem(image, 1), elem(caption, 1)]}
  end

  @impl Kotoba.Node
  def render_text(node, _opts), do: node.name

  @impl Kotoba.Node
  def render_markdown(node, opts) do
    name = Markdown.escape(node.name)

    cond do
      not Renderer.policy(opts).attachments -> name
      image?(node) -> "![" <> name <> "](" <> Markdown.url(node.url) <> ")"
      true -> "[" <> name <> "](" <> Markdown.url(node.url) <> ")"
    end
  end
end
