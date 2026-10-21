defmodule Kotoba.Nodes.Embed do
  @moduledoc """
  Something live of the app's own in the document (type `"embed"`): a
  canvas, a grid, a chart. The document keeps what the app needs to find
  it, and the app renders it, live, in the editor (`Kotoba.Embeds`). The
  JSON keys are `kind`, `ref` and `title`.

    * `kind` - what it is, in the app's words, for example `"canvas"`.
    * `ref` - which one, for example the canvas's id, as a string.
    * `title` - its title, for the text and the Markdown of the document,
      and for a page that renders the document without the app.

  ## Rendering

  Kotoba does not know what an embed is: the app says what it renders as,
  with the `:embed` option of `Kotoba.Renderer` (and of
  `Kotoba.Components.kotoba_content/1`), or for every render (the HTML
  cached when content is cast too) with the config:

      config :kotoba, embed: &MyApp.Embeds.render/2

  The function gets the embed and the format (`:html`, `:markdown` or
  `:text`) and returns what takes its place: safe HTML for `:html` (a
  `~H` template, `{:safe, iodata}`; a string is escaped), Markdown or text
  as a string, or `nil` for the default. For example, a canvas in Markdown
  as a Mermaid diagram (see `Hakushi.Kit.to_markdown/2`):

      def render(%{kind: "canvas", ref: id}, :markdown),
        do: Diagrams.get!(id) |> then(&Hakushi.Kit.to_markdown(&1.kits, &1.graph))

      def render(_embed, _format), do: nil

  By default, an embed is its title: a `div.kotoba-embed` with its kind
  and ref in HTML, which a page can fill with the app's content, and the
  title in text and Markdown. See the [Embeds](embeds.md) guide.

  ## In Markdown, and back

  In Markdown, an embed is what the app renders (or its title) between two
  comments that say what it is, which Markdown viewers leave out:

      <!-- kotoba:embed {"kind":"grid","ref":"7","title":"Open tasks"} -->

      | Task | Due |
      | --- | --- |
      | Write the guide | 2026-11-02 |

      <!-- /kotoba:embed -->

  `Kotoba.Content.from_markdown/2` reads it back as the embed, so a
  document exported to Markdown comes back with its embeds, of any kind.
  """
  use Kotoba.Node, type: "embed", kind: :decorator

  alias Kotoba.Renderer

  field :kind, :string, required: true
  field :ref, :string, required: true
  field :title, :string, default: ""

  @impl Kotoba.Node
  def render_html(node, opts) do
    with nil <- app(node, :html, opts) do
      Renderer.tag(
        "div",
        [class: "kotoba-embed", "data-kind": node.kind, "data-ref": node.ref],
        node.title || ""
      )
    end
  end

  @impl Kotoba.Node
  def render_text(node, opts), do: app(node, :text, opts) || node.title || ""

  @end_marker "<!-- /kotoba:embed -->"

  @impl Kotoba.Node
  def render_markdown(node, opts) do
    content = app(node, :markdown, opts) || Kotoba.Markdown.escape(node.title || "")
    marker(node) <> "\n\n" <> content <> "\n\n" <> @end_marker
  end

  @doc false
  # The comment that says what the Markdown after it is. Its JSON has no
  # "--", which would end the comment.
  def marker(node) do
    json =
      %{"kind" => node.kind, "ref" => node.ref, "title" => node.title || ""}
      |> JSON.encode!()
      |> String.replace("--", "-\\u002d")

    "<!-- kotoba:embed " <> json <> " -->"
  end

  @doc false
  def end_marker, do: @end_marker

  @doc false
  # The embed a comment says, or :error.
  def read_marker(html) do
    with [_, json] <- Regex.run(~r/\A<!--\s*kotoba:embed\s+(\{.*\})\s*-->\s*\z/s, html),
         {:ok, %{"kind" => kind, "ref" => ref} = embed} when is_binary(kind) and is_binary(ref) <-
           JSON.decode(json) do
      {:ok, %{kind: kind, ref: ref, title: to_string(embed["title"] || "")}}
    else
      _ -> :error
    end
  end

  # The app's rendering: the `:embed` option, else the config.
  defp app(node, format, opts) do
    case Keyword.get(opts, :embed) || Application.get_env(:kotoba, :embed) do
      nil -> nil
      fun when is_function(fun, 2) -> fun.(node, format)
      {module, function} -> apply(module, function, [node, format])
    end
  end
end
