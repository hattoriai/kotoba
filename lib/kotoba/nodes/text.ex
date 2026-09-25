defmodule Kotoba.Nodes.Text do
  @moduledoc """
  A run of text (Lexical type `"text"`).

  `format` is a bitmask of text formats. Use `formats/1` and `format?/2` to
  read it:

  | Format           | Bit   |
  | ---------------- | ----- |
  | `:bold`          | `1`   |
  | `:italic`        | `2`   |
  | `:strikethrough` | `4`   |
  | `:underline`     | `8`   |
  | `:code`          | `16`  |
  | `:subscript`     | `32`  |
  | `:superscript`   | `64`  |
  | `:highlight`     | `128` |
  | `:lowercase`     | `256` |
  | `:uppercase`     | `512` |
  | `:capitalize`    | `1024` |

  In HTML, the formats become `strong`, `em`, `s`, `u`, `code`, `sub`,
  `sup` and `mark`, and the three text transforms become `span` elements
  with the classes `kotoba-lowercase`, `kotoba-uppercase` and
  `kotoba-capitalize`. The `style` of the run is not rendered.

  `mode` is `"normal"`, `"token"` or `"segmented"`. `detail` is a bitmask
  that Lexical uses for special characters. `style` is an inline CSS text
  that Lexical keeps for the run.
  """
  use Kotoba.Node, type: "text", kind: :inline

  import Bitwise

  alias Kotoba.{Markdown, Renderer}

  field :text, :string, required: true
  field :format, :integer, default: 0
  field :style, :string, default: ""
  field :mode, :string, default: "normal", in: ~w(normal token segmented)
  field :detail, :integer, default: 0

  @typedoc "A text format."
  @type format ::
          :bold
          | :italic
          | :strikethrough
          | :underline
          | :code
          | :subscript
          | :superscript
          | :highlight
          | :lowercase
          | :uppercase
          | :capitalize

  @formats [
    bold: 1,
    italic: 2,
    strikethrough: 4,
    underline: 8,
    code: 16,
    subscript: 32,
    superscript: 64,
    highlight: 128,
    lowercase: 256,
    uppercase: 512,
    capitalize: 1024
  ]

  @doc """
  Returns the formats that are set in a format bitmask, or in the bitmask of
  a text node.

  ## Examples

      iex> Kotoba.Nodes.Text.formats(3)
      [:bold, :italic]

      iex> Kotoba.Nodes.Text.formats(%Kotoba.Nodes.Text{text: "x", format: 16})
      [:code]

  """
  @spec formats(integer() | %{format: integer()}) :: [format()]
  def formats(%{format: bitmask}), do: formats(bitmask)

  def formats(bitmask) when is_integer(bitmask),
    do: for({name, bit} <- @formats, (bitmask &&& bit) != 0, do: name)

  @doc """
  Returns `true` when the format is set in a format bitmask, or in the
  bitmask of a text node.

  ## Examples

      iex> Kotoba.Nodes.Text.format?(1, :bold)
      true

      iex> Kotoba.Nodes.Text.format?(1, :italic)
      false

  """
  @spec format?(integer() | %{format: integer()}, format()) :: boolean()
  def format?(%{format: bitmask}, format), do: format?(bitmask, format)

  def format?(bitmask, format) when is_integer(bitmask),
    do: (bitmask &&& Keyword.fetch!(@formats, format)) != 0

  @doc """
  Returns the format bitmask for a list of formats.

  ## Examples

      iex> Kotoba.Nodes.Text.bitmask([:bold, :code])
      17

  """
  @spec bitmask([format()]) :: non_neg_integer()
  def bitmask(formats) when is_list(formats) do
    formats |> Enum.map(&Keyword.fetch!(@formats, &1)) |> Enum.reduce(0, &bor/2)
  end

  @html [
    bold: {"strong", nil},
    italic: {"em", nil},
    strikethrough: {"s", nil},
    underline: {"u", nil},
    code: {"code", nil},
    subscript: {"sub", nil},
    superscript: {"sup", nil},
    highlight: {"mark", nil},
    lowercase: {"span", "kotoba-lowercase"},
    uppercase: {"span", "kotoba-uppercase"},
    capitalize: {"span", "kotoba-capitalize"}
  ]

  @markdown [bold: "**", italic: "*", strikethrough: "~~"]

  @impl Kotoba.Node
  def render_html(%{text: ""}, _opts), do: {:safe, ""}

  def render_html(node, _opts) do
    node
    |> formats()
    |> Enum.reverse()
    |> Enum.reduce(Phoenix.HTML.html_escape(node.text), fn format, inner ->
      {tag, class} = Keyword.fetch!(@html, format)
      Renderer.tag(tag, [class: class], inner)
    end)
  end

  @impl Kotoba.Node
  def render_text(node, _opts), do: node.text

  @impl Kotoba.Node
  def render_markdown(%{text: ""}, _opts), do: ""

  def render_markdown(node, _opts) do
    formats = formats(node)

    text =
      if :code in formats, do: Markdown.code_span(node.text), else: Markdown.escape(node.text)

    @markdown
    |> Enum.filter(fn {format, _marker} -> format in formats end)
    |> Enum.reverse()
    |> Enum.reduce(text, fn {_format, marker}, inner -> Markdown.wrap(inner, marker) end)
  end
end
