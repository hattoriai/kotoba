defmodule Kotoba.Renderer do
  @moduledoc """
  Renders a `Kotoba.Document` as HTML, as plain text and as Markdown.

  `to_html/2` returns safe iodata from `Phoenix.HTML`. Every string in the
  document is escaped, and Kotoba never passes raw HTML through. Before it
  renders a node, the renderer calls `Kotoba.Sanitizer.check/3`. A node
  that fails the check renders as an unknown node:
  `<span class="kotoba-unknown" data-type="...">` with no content.

  ## HTML of the built-in nodes

  | Node               | HTML                                                   |
  | ------------------ | ------------------------------------------------------ |
  | paragraph          | `p`                                                    |
  | heading            | `h1` to `h4` (`h5` and `h6` become `h4`)               |
  | quote              | `blockquote`                                           |
  | list               | `ul`, `ol` (with `start` when it is not 1), `ul.kotoba-check` |
  | list item          | `li`; in a check list `li.kotoba-checked` or `li.kotoba-unchecked` |
  | code               | `pre` with `code.language-<language>`, the text escaped |
  | text               | the text in `strong`, `em`, `s`, `u`, `code`, `sub`, `sup`, `mark`, and `span.kotoba-lowercase`, `span.kotoba-uppercase`, `span.kotoba-capitalize` |
  | line break         | `br`                                                   |
  | horizontal rule    | `hr`                                                   |
  | link, autolink     | `a` with `rel="noopener nofollow"`, or the text when the URL is not safe |
  | attachment         | `figure.kotoba-attachment` with an `img`, or a download link, and a `figcaption` |
  | mention            | `span.kotoba-mention` with `data-kind` and `data-id`   |
  | tab                | a tab character, escaped                               |
  | unknown            | `span.kotoba-unknown` with `data-type`                 |

  ## Options

    * `:policy` - `:default` or `:untrusted`. See `Kotoba.Sanitizer`. The
      default is `:default`.
    * `:schemes` - the allowed link schemes. See `Kotoba.Sanitizer.link_url/2`.

  ## The options of the render callbacks

  The renderer gives the options above to each render callback of a node,
  with these changes:

    * `:policy` - the policy map from `Kotoba.Sanitizer.policy/1`.
    * `:parent` - the parent node, or `nil` for the root node.
    * `:index` - the position of the node among the children of its
      parent, or `nil` for the root node.

  A node gives the same `opts` to `html_children/2`, `text_children/2` and
  `markdown_children/3`.
  """

  alias Kotoba.{Document, Sanitizer}
  alias Kotoba.Nodes.{Root, Unknown}

  @typedoc "An attribute of an HTML tag. A `nil` or `false` value is left out."
  @type attribute :: {atom() | String.t(), String.t() | integer() | boolean() | nil}

  @doc """
  Renders a document as safe HTML.

  ## Examples

      iex> {:ok, doc} =
      ...>   Kotoba.Document.parse(%{
      ...>     "kotoba" => 1,
      ...>     "lexical" => "0.51",
      ...>     "root" => %{
      ...>       "type" => "root",
      ...>       "children" => [
      ...>         %{"type" => "paragraph", "children" => [%{"type" => "text", "text" => "<b>hi</b>"}]}
      ...>       ]
      ...>     }
      ...>   })
      iex> doc |> Kotoba.Renderer.to_html() |> Phoenix.HTML.safe_to_string()
      "<p>&lt;b&gt;hi&lt;/b&gt;</p>"

  """
  @spec to_html(Document.t(), keyword()) :: Phoenix.HTML.safe()
  def to_html(%Document{root: root}, opts \\ []) do
    {:safe, render(root, nil, :html, prepare(opts))}
  end

  @doc """
  Renders a document as plain text. Blocks are separated by `"\\n"`.
  """
  @spec to_text(Document.t(), keyword()) :: String.t()
  def to_text(%Document{root: root}, opts \\ []), do: render(root, nil, :text, prepare(opts))

  @doc """
  Renders a document as Markdown, as well as Markdown can show it.

  Headings, lists, code blocks, bold, italic, strikethrough, inline code,
  links and images become Markdown. The other nodes and formats give their
  plain text. Blocks are separated by a blank line.
  """
  @spec to_markdown(Document.t(), keyword()) :: String.t()
  def to_markdown(%Document{root: root}, opts \\ []),
    do: render(root, nil, :markdown, prepare(opts))

  @doc """
  Renders the children of an element node as safe HTML.
  """
  @spec html_children(Kotoba.Node.t(), keyword()) :: Phoenix.HTML.safe()
  def html_children(node, opts) do
    opts = prepare(opts)

    html =
      node
      |> children()
      |> Enum.with_index()
      |> Enum.map(fn {child, index} -> render(child, node, :html, indexed(opts, index)) end)

    {:safe, html}
  end

  @doc """
  Renders the children of an element node as plain text.

  Consecutive inline nodes are joined. Each block child gives one line, and
  the lines are separated by `"\\n"`. A decorator in the root node is a
  block; it gives no line when it has no text.
  """
  @spec text_children(Kotoba.Node.t(), keyword()) :: String.t()
  def text_children(node, opts) do
    opts = prepare(opts)

    node
    |> segments(:text, opts)
    |> Enum.reject(fn {block, text} -> block == :decorator and text == "" end)
    |> Enum.map_join("\n", &elem(&1, 1))
  end

  @doc """
  Renders the children of an element node as Markdown.

  Consecutive inline nodes are joined. The blocks are separated by
  `separator` (the default is a blank line). Empty blocks are left out.
  """
  @spec markdown_children(Kotoba.Node.t(), keyword(), String.t()) :: String.t()
  def markdown_children(node, opts, separator \\ "\n\n") do
    opts = prepare(opts)

    node
    |> segments(:markdown, opts)
    |> Enum.reject(fn {_block, markdown} -> markdown == "" end)
    |> Enum.map_join(separator, &elem(&1, 1))
  end

  @doc """
  Renders each child of an element node as Markdown. Returns a list of
  `{child, markdown}` tuples, in order.
  """
  @spec markdown_each(Kotoba.Node.t(), keyword()) :: [{Kotoba.Node.t(), String.t()}]
  def markdown_each(node, opts) do
    opts = prepare(opts)

    node
    |> children()
    |> Enum.with_index()
    |> Enum.map(fn {child, index} ->
      {child, render(child, node, :markdown, indexed(opts, index))}
    end)
  end

  @doc """
  Returns an HTML tag as safe HTML.

  The attribute values and a string `content` are escaped. `content` can
  also be safe HTML. A `nil` or `false` attribute is left out, and a `true`
  attribute has no value. When `content` is `:void`, the tag has no end tag.

  ## Examples

      iex> Kotoba.Renderer.tag("a", [href: "/x?a=1&b=2", title: nil], "A & B") |> Phoenix.HTML.safe_to_string()
      ~s(<a href="/x?a=1&amp;b=2">A &amp; B</a>)

      iex> Kotoba.Renderer.tag("br", [], :void) |> Phoenix.HTML.safe_to_string()
      "<br>"

  """
  @spec tag(String.t(), [attribute()], Phoenix.HTML.safe() | String.t() | :void) ::
          Phoenix.HTML.safe()
  def tag(name, attrs, :void), do: {:safe, ["<", name, attributes(attrs), ">"]}

  def tag(name, attrs, content) do
    {:safe, body} = Phoenix.HTML.html_escape(content)
    {:safe, ["<", name, attributes(attrs), ">", body, "</", name, ">"]}
  end

  defp attributes(attrs) do
    for {name, value} <- attrs, value not in [nil, false] do
      case value do
        true -> [" ", to_string(name)]
        value -> [" ", to_string(name), "=\"", escape(to_string(value)), "\""]
      end
    end
  end

  defp escape(string) do
    {:safe, iodata} = Phoenix.HTML.html_escape(string)
    iodata
  end

  @doc """
  Escapes the Markdown characters in a plain string, for a
  `c:Kotoba.Node.render_markdown/2` callback.

  It escapes the inline syntax everywhere (`` ` ``, `*`, `_`, `[`, `]`,
  `~`, `<`, `&` and `\\`), and the block syntax at the start of a line: `#`
  headings, `>` quotes, `-` and `+` bullets, `1.` and `1)` list markers,
  and `---` or `===` lines. So a node that renders its text at the start
  of a block cannot make a heading or a list.

  ## Examples

      iex> Kotoba.Renderer.escape_markdown("*not* [a link]")
      "\\\\*not\\\\* \\\\[a link\\\\]"

      iex> Kotoba.Renderer.escape_markdown("# not a heading")
      "\\\\# not a heading"

      iex> Kotoba.Renderer.escape_markdown("1. not a list")
      "1\\\\. not a list"

  """
  @spec escape_markdown(String.t()) :: String.t()
  def escape_markdown(text) when is_binary(text), do: Kotoba.Markdown.escape(text)

  @doc """
  Returns a URL for the destination of a Markdown link, for a
  `c:Kotoba.Node.render_markdown/2` callback. Spaces and parentheses are
  percent-encoded, and `\\`, `&`, `<` and `>` get a backslash, so that a
  CommonMark renderer decodes no entity. Check the URL with
  `Kotoba.Sanitizer.link_url/2` first.

  ## Examples

      iex> Kotoba.Renderer.escape_markdown_url("/docs/a page (draft)")
      "/docs/a%20page%20%28draft%29"

      iex> Kotoba.Renderer.escape_markdown_url("/search?q=a&b")
      "/search?q=a\\\\&b"

  """
  @spec escape_markdown_url(String.t()) :: String.t()
  def escape_markdown_url(url) when is_binary(url), do: Kotoba.Markdown.url(url)

  @doc """
  Returns the safe HTML of an unknown node of `type`.
  """
  @spec unknown_html(String.t()) :: Phoenix.HTML.safe()
  def unknown_html(type), do: tag("span", [class: "kotoba-unknown", "data-type": type], "")

  @doc """
  Returns the policy map of the render options. See `Kotoba.Sanitizer.policy/1`.
  """
  @spec policy(keyword()) :: Sanitizer.policy()
  def policy(opts), do: Sanitizer.policy(Keyword.get(opts, :policy, :default))

  defp prepare(opts) when is_list(opts) do
    Keyword.put(opts, :policy, Sanitizer.policy(Keyword.get(opts, :policy, :default)))
  end

  defp render(%Unknown{type: type}, _parent, format, _opts), do: unknown(format, type)

  defp render(%module{} = node, parent, format, opts) do
    case Sanitizer.check(node, parent, opts) do
      :ok -> call(module, format, node, Keyword.put(opts, :parent, parent))
      {:error, _reason} -> unknown(format, module.type())
    end
  end

  defp call(module, :html, node, opts) do
    {:safe, iodata} = node |> module.render_html(opts) |> Phoenix.HTML.html_escape()
    iodata
  end

  defp call(module, :text, node, opts), do: module.render_text(node, opts)
  defp call(module, :markdown, node, opts), do: module.render_markdown(node, opts)

  defp unknown(:html, type), do: type |> unknown_html() |> elem(1)
  defp unknown(_format, _type), do: ""

  # A segment is one line of text or one block of Markdown: a run of inline
  # nodes (`:inline`), a block node (`:block`), or a decorator or an
  # unknown node in the root (`:decorator`).
  defp segments(node, format, opts) do
    node
    |> children()
    |> Enum.with_index()
    |> Enum.chunk_by(fn {child, _index} -> level(child, node) end)
    |> Enum.flat_map(&segment_chunk(&1, node, format, opts))
  end

  defp segment_chunk([{first, _index} | _rest] = chunk, node, format, opts) do
    case level(first, node) do
      :inline -> [{:inline, Enum.map_join(chunk, &render_indexed(&1, node, format, opts))}]
      level -> Enum.map(chunk, &{level, render_indexed(&1, node, format, opts)})
    end
  end

  defp render_indexed({child, index}, node, format, opts),
    do: render(child, node, format, indexed(opts, index))

  defp indexed(opts, index), do: Keyword.put(opts, :index, index)

  defp level(%Unknown{}, %Root{}), do: :decorator
  defp level(%Unknown{}, _parent), do: :inline

  defp level(%module{}, parent) do
    case {module.kind(), parent} do
      {:block, _parent} -> :block
      {:decorator, %Root{}} -> :decorator
      _other -> :inline
    end
  end

  defp children(%{children: children}) when is_list(children), do: children
  defp children(_node), do: []
end
