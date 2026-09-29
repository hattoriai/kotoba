defmodule Kotoba.Nodes.Attachment do
  @moduledoc """
  A file in the document (type `"attachment"`), for example an image.

  The JSON keys are camelCase, as in Lexical: `key`, `url`, `name`,
  `contentType`, `bytes`, `width` and `height`.

  In HTML, an attachment is a `figure` with the class `kotoba-attachment`:

    * An image has an `img` and a `figcaption` with the name.
    * A PDF (`figure.kotoba-attachment-pdf`) has an `object` that shows it
      in the browser's viewer, with a download link inside for a browser
      that has none; with a `preview`, a link to the PDF with the preview
      image instead.
    * A video (`figure.kotoba-attachment-video`) has a `video` with
      controls, `preload="metadata"`, no autoplay, the `preview` as its
      poster, and a download link inside.
    * Another file has only its `figcaption`. The `figcaption` of a PDF, a
      video and another file is a download link.

  With the `:untrusted` policy, only the name is rendered.

    * `key` - the storage key of the file.
    * `url` - the URL of the file.
    * `name` - the file name.
    * `content_type` - the media type, for example `"image/png"`.
    * `bytes` - the size of the file.
    * `width` and `height` - the size of an image in pixels, or `nil`.
    * `preview` - the URL of an image of a PDF's first page or a video's
      poster frame, or `nil`. The app makes it (see the `:preview` option of
      `Kotoba.Live.consume_uploads/4`).
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
  field :preview, :string, omit_nil: true

  @doc """
  Returns `true` when the attachment is an image.

  ## Examples

      iex> Kotoba.Nodes.Attachment.image?(%Kotoba.Nodes.Attachment{content_type: "image/png"})
      true

  """
  @spec image?(t()) :: boolean()
  def image?(%{content_type: "image/" <> _subtype}), do: true
  def image?(%{content_type: _content_type}), do: false

  @doc "Returns `true` when the attachment is a PDF."
  @spec pdf?(t()) :: boolean()
  def pdf?(%{content_type: type}), do: type == "application/pdf"

  @doc "Returns `true` when the attachment is a video (`video/mp4` or `video/webm`)."
  @spec video?(t()) :: boolean()
  def video?(%{content_type: type}), do: type in ["video/mp4", "video/webm"]

  @impl Kotoba.Node
  def render_html(node, opts) do
    if Renderer.policy(opts).attachments do
      url = Sanitizer.link_url(node.url, opts)
      preview = node.preview && Sanitizer.link_url(node.preview, opts)
      Renderer.tag("figure", [class: class(node)], figure(node, url, preview))
    else
      Phoenix.HTML.html_escape(node.name)
    end
  end

  defp class(node) do
    cond do
      pdf?(node) -> "kotoba-attachment kotoba-attachment-pdf"
      video?(node) -> "kotoba-attachment kotoba-attachment-video"
      true -> "kotoba-attachment"
    end
  end

  defp figure(node, url, preview) do
    if image?(node) do
      join([
        Renderer.tag(
          "img",
          [src: url, alt: node.name, width: node.width, height: node.height],
          :void
        ),
        Renderer.tag("figcaption", [], node.name)
      ])
    else
      join([media(node, url, preview), Renderer.tag("figcaption", [], download(node, url))])
    end
  end

  defp media(node, url, preview) do
    cond do
      pdf?(node) and preview != nil ->
        image = Renderer.tag("img", [src: preview, alt: "Preview of " <> node.name], :void)
        Renderer.tag("a", [href: url, rel: "noopener nofollow"], image)

      pdf?(node) ->
        Renderer.tag(
          "object",
          [data: url, type: "application/pdf", "aria-label": node.name],
          download(node, url)
        )

      video?(node) ->
        Renderer.tag(
          "video",
          [
            src: url,
            controls: true,
            preload: "metadata",
            playsinline: true,
            poster: preview,
            "aria-label": node.name
          ],
          download(node, url)
        )

      true ->
        {:safe, ""}
    end
  end

  defp download(node, url),
    do: Renderer.tag("a", [href: url, download: true, rel: "noopener nofollow"], node.name)

  defp join(parts), do: {:safe, Enum.map(parts, &elem(&1, 1))}

  @impl Kotoba.Node
  def render_text(node, _opts), do: node.name

  @impl Kotoba.Node
  def render_markdown(node, opts) do
    name = Markdown.escape(node.name)

    destination = Markdown.destination(node.url)

    cond do
      not Renderer.policy(opts).attachments or destination == nil -> name
      image?(node) -> "![" <> name <> "](" <> destination <> ")"
      true -> "[" <> name <> "](" <> destination <> ")"
    end
  end
end
