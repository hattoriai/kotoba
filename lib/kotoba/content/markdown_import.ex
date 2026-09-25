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
  @inline ~r/
    `(?<code>[^`]+)`
    |\*\*(?<bold>[^*]+)\*\*
    |_(?<italic>[^_]+)_
    |\[(?<text>[^\]]*)\]\((?<url>[^)\s]+)\)
  /x

  @doc "Returns the root node JSON for a Markdown string."
  @spec root(String.t()) :: map()
  def root(markdown) do
    children = markdown |> String.split(~r/\r\n|\r|\n/) |> blocks([])
    element("root", children)
  end

  defp blocks([], acc), do: Enum.reverse(acc)
  defp blocks(["" | rest], acc), do: blocks(rest, acc)

  defp blocks([line | rest] = lines, acc) do
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
    children = body |> Enum.map(&text_node/1) |> Enum.intersperse(linebreak_node())

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

  defp plain_line?(""), do: false

  defp plain_line?(line),
    do:
      not Regex.match?(@fence, line) and not Regex.match?(@heading, line) and not item_line?(line)

  # -- inline ----------------------------------------------------------------

  defp inline(""), do: []

  defp inline(text) do
    case Regex.run(@inline, text) do
      nil ->
        [text_node(text)]

      [whole | _groups] ->
        captures = Regex.named_captures(@inline, text)
        [before, rest] = String.split(text, whole, parts: 2)
        before_nodes = if before == "", do: [], else: [text_node(before)]
        before_nodes ++ [token(captures)] ++ inline(rest)
    end
  end

  defp token(%{"code" => code, "bold" => bold, "italic" => italic, "text" => text, "url" => url}) do
    cond do
      present?(code) -> text_node(code, 16)
      present?(bold) -> text_node(bold, 1)
      present?(italic) -> text_node(italic, 2)
      true -> link_node(url, [text_node(text)])
    end
  end

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
