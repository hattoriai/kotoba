defmodule Kotoba.Content.MarkdownImport do
  @moduledoc false
  # A small Markdown to Lexical root converter for
  # `Kotoba.Content.from_markdown/2`. It reads what Kotoba's own Markdown
  # writes (see `Kotoba.Renderer.to_markdown/2`), and the common GitHub
  # Flavored Markdown around it:
  #
  #   * paragraphs, `#` headings, `>` quotes, horizontal rules (`---`,
  #     `***`, `___`), fenced code blocks;
  #   * `-`/`*`/`1.` lists (one level; a numbered list keeps its first
  #     number), `- [ ]`/`- [x]` check lists;
  #   * pipe tables, with a header row;
  #   * the inline `**bold**`, `*italic*`/`_italic_`, `***both***`,
  #     `~~strikethrough~~`, `` `code` `` and `[text](url)`, which nest
  #     (a link in bold, bold in a link).
  #
  # Anything else becomes plain paragraph text.

  import Bitwise

  @heading ~r/\A(#+)\s+(.*)\z/
  @fence ~r/\A```(\w*)\s*\z/
  @rule ~r/\A {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*\z/
  @quote ~r/\A {0,3}> ?(.*)\z/
  @check ~r/\A[-*]\s+\[([ xX])\]\s+(.*)\z/
  @bullet ~r/\A[-*]\s+(.*)\z/
  @numbered ~r/\A(\d+)\.\s+(.*)\z/
  @table_row ~r/\A\s*\|.*\|\s*\z/
  @table_separator ~r/\A\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*\z/

  # The first match from the left wins, and at one place the first
  # alternative: `***` before `**` before `*`.
  #
  # `_italic_` requires a non-word character (or a string edge) on each
  # side, so `snake_case_name` is not read as emphasis; `*italic*` requires
  # text that does not start or end with a space, so `2 * 3 * 4` is not.
  # `url` allows one level of balanced parentheses, so a Wikipedia-style URL
  # is not cut at the first `)`.
  @inline ~r/
    `(?<code>[^`]+)`
    |\[(?<text>[^\]]*)\]\((?<url>(?:[^()\s]|\([^()\s]*\))+)\)
    |\*\*\*(?<both>[^*]+)\*\*\*
    |\*\*(?<bold>.+?)\*\*
    |~~(?<strike>.+?)~~
    |(?<![\w*])\*(?<star>[^\s*](?:[^*]*[^\s*])?)\*(?![\w*])
    |(?<!\w)_(?<italic>[^_]+)_(?!\w)
  /x

  @inline_names Regex.names(@inline)

  @bold 1
  @italic 2
  @strikethrough 4
  @code 16

  @doc "Returns the root node JSON for a Markdown string."
  @spec root(String.t()) :: map()
  def root(markdown) do
    children = markdown |> String.split(~r/\r\n|\r|\n/) |> blocks([])
    element("root", children)
  end

  defp blocks([], acc), do: Enum.reverse(acc)

  defp blocks([line | rest] = lines, acc) do
    if String.trim(line) == "" do
      blocks(rest, acc)
    else
      dispatch_block(lines, acc)
    end
  end

  defp dispatch_block([line | rest] = lines, acc) do
    cond do
      match = Regex.run(@fence, line, capture: :all_but_first) ->
        {code, rest} = code_block(rest, match)
        blocks(rest, [code | acc])

      Regex.match?(@heading, line) ->
        blocks(rest, [heading(line) | acc])

      Regex.match?(@rule, line) ->
        blocks(rest, [%{"type" => "horizontalrule", "version" => 1} | acc])

      table_start?(lines) ->
        {table, rest} = table_block(lines)
        blocks(rest, [table | acc])

      Regex.match?(@quote, line) ->
        {quote, rest} = quote_block(lines)
        blocks(rest, [quote | acc])

      item_kind(line) != nil ->
        {list, rest} = list_block(lines)
        blocks(rest, [list | acc])

      true ->
        {paragraph, rest} = paragraph_block(lines)
        blocks(rest, [paragraph | acc])
    end
  end

  # -- code ------------------------------------------------------------

  defp code_block(lines, [language]) do
    {body, rest} = Enum.split_while(lines, &(not Regex.match?(@fence, &1)))
    rest = drop_fence(rest)

    # A blank line in the fence gets a line break with no text node either
    # side of it, not an empty text node.
    children =
      body
      |> Enum.map(&if(&1 == "", do: [], else: [text_node(&1)]))
      |> Enum.intersperse([linebreak_node()])
      |> List.flatten()

    code = element("code", children)
    code = if language == "", do: code, else: Map.put(code, "language", language)
    {code, rest}
  end

  defp drop_fence([_close | tail]), do: tail
  defp drop_fence([]), do: []

  # -- headings ----------------------------------------------------------

  defp heading(line) do
    [marker, content] = Regex.run(@heading, line, capture: :all_but_first)
    level = marker |> String.length() |> min(6)
    element("heading", inline(String.trim(content)), %{"tag" => "h#{level}"})
  end

  # -- quotes ------------------------------------------------------------

  # The lines that start with `>`; a quote holds inline content, so its
  # lines are joined with line breaks.
  defp quote_block(lines) do
    {quote_lines, rest} = Enum.split_while(lines, &Regex.match?(@quote, &1))

    children =
      quote_lines
      |> Enum.map(fn line ->
        [content] = Regex.run(@quote, line, capture: :all_but_first)
        inline(String.trim(content))
      end)
      |> Enum.intersperse([linebreak_node()])
      |> List.flatten()

    {element("quote", children), rest}
  end

  # -- lists ---------------------------------------------------------------

  defp item_kind(line) do
    cond do
      Regex.match?(@check, line) -> :check
      Regex.match?(@bullet, line) -> :bullet
      Regex.match?(@numbered, line) -> :number
      true -> nil
    end
  end

  # The items of one kind: a line of another kind starts another list.
  defp list_block([first | _] = lines) do
    kind = item_kind(first)
    {item_lines, rest} = Enum.split_while(lines, &(item_kind(&1) == kind))
    start = if kind == :number, do: number(first), else: 1

    items =
      item_lines
      |> Enum.with_index(start)
      |> Enum.map(fn {line, value} -> list_item(kind, line, value) end)

    tag = if kind == :number, do: "ol", else: "ul"

    list =
      element("list", items, %{"listType" => to_string(kind), "start" => start, "tag" => tag})

    {list, rest}
  end

  defp number(line) do
    [digits, _content] = Regex.run(@numbered, line, capture: :all_but_first)
    String.to_integer(digits)
  end

  defp list_item(:check, line, value) do
    [mark, content] = Regex.run(@check, line, capture: :all_but_first)
    element("listitem", inline(content), %{"value" => value, "checked" => mark != " "})
  end

  defp list_item(:bullet, line, value) do
    [content] = Regex.run(@bullet, line, capture: :all_but_first)
    element("listitem", inline(content), %{"value" => value})
  end

  defp list_item(:number, line, value) do
    [_digits, content] = Regex.run(@numbered, line, capture: :all_but_first)
    element("listitem", inline(content), %{"value" => value})
  end

  # -- tables ----------------------------------------------------------------

  # A row of cells, then a separator row (`| --- | :-: |`).
  defp table_start?([line, separator | _]),
    do: Regex.match?(@table_row, line) and Regex.match?(@table_separator, separator)

  defp table_start?(_lines), do: false

  defp table_block([header, _separator | lines]) do
    {body, rest} = Enum.split_while(lines, &Regex.match?(@table_row, &1))
    width = header |> cells() |> length()

    rows = [
      table_row(cells(header), width, 1)
      | Enum.map(body, &table_row(cells(&1), width, 0))
    ]

    {element("table", rows), rest}
  end

  # Every row has the width of the header row: a short row gets empty
  # cells, and the cells of a long row past it are dropped.
  defp table_row(cells, width, header_state) do
    cells =
      cells
      |> Enum.take(width)
      |> then(&(&1 ++ List.duplicate("", width - length(&1))))
      |> Enum.map(fn text ->
        paragraph = element("paragraph", inline(text), %{"textFormat" => 0, "textStyle" => ""})

        element("tablecell", [paragraph], %{
          "headerState" => header_state,
          "colSpan" => 1,
          "rowSpan" => 1
        })
      end)

    element("tablerow", cells)
  end

  # The cells of a row: split at the `|` that are not escaped (`\|`).
  defp cells(line) do
    line
    |> String.trim()
    |> String.replace(~r/\A\|/, "")
    |> String.replace(~r/(?<!\\)\|\z/, "")
    |> String.split(~r/(?<!\\)\|/)
    |> Enum.map(&(&1 |> String.replace("\\|", "|") |> String.trim()))
  end

  # -- paragraphs ------------------------------------------------------------

  defp paragraph_block(lines) do
    {para_lines, rest} = Enum.split_while(lines, &plain_line?/1)

    children =
      para_lines
      |> Enum.map(&inline(String.trim(&1)))
      |> Enum.intersperse([linebreak_node()])
      |> List.flatten()

    {element("paragraph", children, %{"textFormat" => 0, "textStyle" => ""}), rest}
  end

  defp plain_line?(line) do
    String.trim(line) != "" and not Regex.match?(@fence, line) and
      not Regex.match?(@heading, line) and not Regex.match?(@rule, line) and
      not Regex.match?(@quote, line) and item_kind(line) == nil
  end

  # -- inline ----------------------------------------------------------------

  defp inline(text, format \\ 0)

  defp inline("", _format), do: []

  defp inline(text, format) do
    case Regex.run(@inline, text, capture: [0 | @inline_names], return: :index) do
      nil ->
        [text_node(text, format)]

      [{start, len} | group_indices] ->
        before = binary_part(text, 0, start)
        rest = binary_part(text, start + len, byte_size(text) - start - len)
        captures = @inline_names |> Enum.zip(group_indices) |> Map.new(&capture(text, &1))
        before_nodes = if before == "", do: [], else: [text_node(before, format)]
        before_nodes ++ token(captures, format) ++ inline(rest, format)
    end
  end

  # `return: :index` gives byte offsets.
  defp capture(_text, {name, {-1, 0}}), do: {name, ""}
  defp capture(text, {name, {start, len}}), do: {name, binary_part(text, start, len)}

  # A link with no text (`[](url)`) gives no node at all, rather than an
  # empty anchor.
  defp token(captures, format) do
    cond do
      present?(captures["code"]) -> [text_node(captures["code"], format ||| @code)]
      present?(captures["url"]) -> link(captures["text"], captures["url"], format)
      present?(captures["both"]) -> inline(captures["both"], format ||| @bold ||| @italic)
      present?(captures["bold"]) -> inline(captures["bold"], format ||| @bold)
      present?(captures["strike"]) -> inline(captures["strike"], format ||| @strikethrough)
      present?(captures["star"]) -> inline(captures["star"], format ||| @italic)
      present?(captures["italic"]) -> inline(captures["italic"], format ||| @italic)
      true -> []
    end
  end

  defp link("", _url, _format), do: []
  defp link(text, url, format), do: [link_node(url, inline(text, format))]

  defp present?(value), do: value not in [nil, ""]

  # -- JSON builders -----------------------------------------------------

  defp element(type, children, attrs \\ %{}) do
    Map.merge(
      %{
        "type" => type,
        "children" => children,
        "direction" => nil,
        "format" => "",
        "indent" => 0,
        "version" => 1
      },
      attrs
    )
  end

  defp text_node(text, format \\ 0) do
    %{
      "type" => "text",
      "detail" => 0,
      "format" => format,
      "mode" => "normal",
      "style" => "",
      "text" => text,
      "version" => 1
    }
  end

  defp linebreak_node, do: %{"type" => "linebreak", "version" => 1}

  defp link_node(url, children) do
    element("link", children, %{"url" => url, "rel" => nil, "target" => nil, "title" => nil})
  end
end
