defmodule Kotoba.Content do
  @moduledoc """
  An `Ecto.Type` that stores a rich text document with a cached rendering.

  A `Kotoba.Content` struct has:

    * `:doc` - the document envelope, as a map with string keys (see
      `Kotoba.Document`).
    * `:html` - the safe HTML of the document, rendered with the
      `:default` policy, as a string.
    * `:text` - the plain text of the document, as a string.
    * `:version` - the content cache version, currently `1`.

  `cast/1` reads a JSON string (as a form posts it through the hidden
  input), a document envelope, a bare Lexical root node (wrapped in an
  envelope), a `Kotoba.Content` struct, `nil` or `""` (both cast to
  `empty/0`). It parses the input through `Kotoba.Document.parse/2`, with
  the node registry from the application configuration, and renders
  `:html` and `:text` right away, so a row always carries a fresh cache.
  Invalid input casts to `:error`, which `Ecto.Changeset` turns into an
  `"is invalid"` error.

  `dump/1` and `load/1` store and read `%{"doc", "html", "text",
  "version"}`. When a loaded map has no `"html"` or no `"text"` (an older
  row, or one written outside Kotoba), `load/1` re-renders them from
  `"doc"`.

  `equal?/2` compares the `:doc` field only, so an `Ecto.Changeset` does
  not mark the field changed when only the cache was recomputed.

  Use `rerender/2` after a node registry or a render policy changes, to
  bring the cache of a stored document up to date. Use `from_markdown/2`
  to build a `Kotoba.Content` from a Markdown string, on a best-effort
  basis.

  ## Examples

      iex> content = Kotoba.Content.empty()
      iex> content.html
      ""
      iex> content.text
      ""

  """

  use Ecto.Type

  alias Kotoba.Content.MarkdownImport
  alias Kotoba.{Document, Renderer}

  @version 1
  @kotoba_version 1
  @lexical_version "0.51"

  @enforce_keys [:doc, :html, :text]
  defstruct doc: nil, html: "", text: "", version: @version

  @type t :: %__MODULE__{
          doc: map(),
          html: String.t(),
          text: String.t(),
          version: pos_integer()
        }

  @impl Ecto.Type
  def type, do: :map

  @doc """
  Casts a JSON string, a document envelope, a bare Lexical root node, a
  `Kotoba.Content` struct, `nil` or `""` to a `Kotoba.Content`.

  Renders `:html` and `:text` at cast time. Returns `:error` when the
  input is not valid JSON, is not an object, or does not parse as a
  `Kotoba.Document` (see `Kotoba.Document.parse/2`).

  ## Examples

      iex> {:ok, content} = Kotoba.Content.cast(%{"type" => "root", "children" => []})
      iex> content.text
      ""

      iex> Kotoba.Content.cast("not json")
      :error

  """
  @impl Ecto.Type
  def cast(%__MODULE__{} = content), do: {:ok, content}
  def cast(nil), do: {:ok, empty()}
  def cast(""), do: {:ok, empty()}

  def cast(json) when is_binary(json) do
    case JSON.decode(json) do
      {:ok, decoded} -> cast(decoded)
      {:error, _reason} -> :error
    end
  end

  def cast(%{"type" => "root"} = root) when is_map(root), do: parse(wrap(root))
  def cast(%{"root" => _root} = envelope) when is_map(envelope), do: parse(envelope)
  def cast(_other), do: :error

  @impl Ecto.Type
  def dump(%__MODULE__{} = content) do
    {:ok,
     %{
       "doc" => content.doc,
       "html" => content.html,
       "text" => content.text,
       "version" => content.version
     }}
  end

  def dump(_other), do: :error

  @impl Ecto.Type
  def load(%{"doc" => doc} = map) when is_map(map) do
    with html when is_binary(html) <- Map.get(map, "html"),
         text when is_binary(text) <- Map.get(map, "text") do
      {:ok,
       %__MODULE__{doc: doc, html: html, text: text, version: Map.get(map, "version", @version)}}
    else
      _missing ->
        case Document.parse(doc) do
          {:ok, parsed} -> {:ok, build(parsed, [])}
          {:error, _messages} -> :error
        end
    end
  end

  def load(_other), do: :error

  @impl Ecto.Type
  def equal?(%__MODULE__{doc: a}, %__MODULE__{doc: b}), do: a == b
  def equal?(_a, _b), do: false

  @impl Ecto.Type
  def embed_as(_format), do: :dump

  @doc """
  Returns an empty `Kotoba.Content`, for a new form or a blank field.
  """
  @spec empty() :: t()
  def empty do
    {:ok, doc} = Document.parse(wrap(%{"type" => "root"}))
    build(doc, [])
  end

  @doc """
  Re-renders `:html` and `:text` from `:doc`, with a node registry and a
  render policy.

  When `:doc` no longer parses (for example a required field that a
  removed custom node used to allow), the content is returned unchanged.

  ## Options

    * `:nodes` - extra node modules for the registry, as in
      `Kotoba.Document.parse/2`.
    * `:policy` - the render policy for `:html`. The default is `:default`.

  """
  @spec rerender(t(), keyword()) :: t()
  def rerender(%__MODULE__{doc: envelope} = content, opts \\ []) do
    {nodes, render_opts} = Keyword.pop(opts, :nodes, [])

    case Document.parse(envelope, nodes: nodes) do
      {:ok, doc} -> build(doc, render_opts)
      {:error, _messages} -> content
    end
  end

  @doc """
  Builds a `Kotoba.Content` from a Markdown string, on a best-effort
  basis.

  Reads paragraphs, `#` headings, `-`/`*`/`1.` lists (one level), fenced
  code blocks, and the inline `**bold**`, `_italic_`, `` `code` `` and
  `[text](url)` syntax. Anything else becomes plain paragraph text. When
  the built document somehow fails to parse, returns `empty/0`.

  ## Options

  Same as `rerender/2`.

  ## Examples

      iex> content = Kotoba.Content.from_markdown("# Title\\n\\nHello **world**.")
      iex> content.text
      "Title\\nHello world."

  """
  @spec from_markdown(String.t(), keyword()) :: t()
  def from_markdown(markdown, opts \\ []) when is_binary(markdown) do
    envelope = wrap(MarkdownImport.root(markdown))
    {nodes, render_opts} = Keyword.pop(opts, :nodes, [])

    case Document.parse(envelope, nodes: nodes) do
      {:ok, doc} -> build(doc, render_opts)
      {:error, _messages} -> empty()
    end
  end

  defp parse(envelope) do
    case Document.parse(envelope) do
      {:ok, doc} -> {:ok, build(doc, [])}
      {:error, _messages} -> :error
    end
  end

  defp build(doc, opts) do
    policy = Keyword.get(opts, :policy, :default)

    html =
      doc |> Renderer.to_html(Keyword.put(opts, :policy, policy)) |> Phoenix.HTML.safe_to_string()

    text = Renderer.to_text(doc, opts)
    %__MODULE__{doc: Document.to_json(doc), html: html, text: text, version: @version}
  end

  defp wrap(root),
    do: %{"kotoba" => @kotoba_version, "lexical" => @lexical_version, "root" => root}
end
