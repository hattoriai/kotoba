defmodule Kotoba.Content.MarkdownImport do
  @moduledoc false
  # A small, best-effort Markdown to Lexical root converter for
  # `Kotoba.Content.from_markdown/2`. It reads paragraphs, `#` headings,
  # `-`/`*`/`1.` lists (one level), fenced code blocks, and the inline
  # `**bold**`, `_italic_`, `` `code` `` and `[text](url)` syntax. Anything
  # else becomes plain paragraph text.

  @heading ~r/\A(#+)\s+(.*)\z/
  @fence ~r/\A```(\w*)\s*\z/
  @bullet ~r/\A[-*]\s+(.*)\z/
  @numbered ~r/\A\d+\.\s+(.*)\z/

  # `italic` requires a non-word character (or a string edge) on each side,
  # so `snake_case_name` is not read as emphasis. `url` allows one level of
  # balanced parentheses, so a Wikipedia-style URL is not cut at the first
  # `)`.
  @inline ~r/
    `(?<code>[^`]+)`
    |\*\*(?<bold>[^*]+)\*\*
    |(?<!\w)_(?<italic>[^_]+)_(?!\w)
    |\[(?<text>[^\]]*)\]\((?<url>(?:[^()\s]|\([^()\s]*\))+)\)
  /x

  @inline_names Regex.names(@inline)

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

      item_line?(line) ->
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

  # -- lists ---------------------------------------------------------------

  defp item_line?(line), do: Regex.match?(@bullet, line) or Regex.match?(@numbered, line)

  defp list_block(lines) do
    {item_lines, rest} = Enum.split_while(lines, &item_line?/1)
    list_type = if Regex.match?(@numbered, hd(item_lines)), do: "number", else: "bullet"
    tag = if list_type == "number", do: "ol", else: "ul"

    items =
      Enum.map(item_lines, fn line ->
        element("listitem", inline(item_text(line)), %{"value" => 1})
      end)

    list = element("list", items, %{"listType" => list_type, "start" => 1, "tag" => tag})
    {list, rest}
  end

  defp item_text(line) do
    case Regex.run(@bullet, line, capture: :all_but_first) do
      [content] ->
        content

      nil ->
        [content] = Regex.run(@numbered, line, capture: :all_but_first)
        content
    end
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
      not Regex.match?(@heading, line) and not item_line?(line)
  end

  # -- inline ----------------------------------------------------------------

  defp inline(""), do: []

  defp inline(text) do
    case Regex.run(@inline, text, capture: [0 | @inline_names], return: :index) do
      nil ->
        [text_node(text)]

      [{start, len} | group_indices] ->
        before = String.slice(text, 0, start)
        rest = String.slice(text, (start + len)..-1//1)
        captures = @inline_names |> Enum.zip(group_indices) |> Map.new(&capture(text, &1))
        before_nodes = if before == "", do: [], else: [text_node(before)]
        before_nodes ++ List.wrap(token(captures)) ++ inline(rest)
    end
  end

  defp capture(_text, {name, {-1, 0}}), do: {name, ""}
  defp capture(text, {name, {start, len}}), do: {name, String.slice(text, start, len)}

  # A link with no text (`[](url)`) gives no node at all, rather than an
  # empty anchor.
  defp token(%{"code" => code, "bold" => bold, "italic" => italic, "text" => text, "url" => url}) do
    cond do
      present?(code) -> text_node(code, 16)
      present?(bold) -> text_node(bold, 1)
      present?(italic) -> text_node(italic, 2)
      present?(text) -> link_node(url, [text_node(text)])
      true -> nil
    end
  end

  defp present?(value), do: value != ""

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
