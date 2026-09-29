defmodule Kotoba.DocumentGenerators do
  @moduledoc """
  StreamData generators of document envelopes in the JSON shape that
  Lexical 0.51 writes, with each built-in node, unknown nodes and extra keys.
  """

  use ExUnitProperties

  @doc "Generates a document envelope."
  def envelope do
    gen all(children <- list_of(block(2), max_length: 4)) do
      %{"kotoba" => 1, "lexical" => "0.51", "root" => element("root", children)}
    end
  end

  @doc """
  Generates one block node. `depth` limits the nesting of lists and
  tables. With `tables?` `false` there is no table, for the blocks of a
  table cell (a table in a table is not valid).
  """
  def block(depth, tables? \\ true) do
    one_of(
      [
        paragraph(),
        heading(),
        quote_block(),
        code(),
        decorator("horizontalrule", %{}),
        attachment(),
        gallery(),
        unknown()
      ] ++
        if(depth > 0, do: [list(depth - 1)], else: []) ++
        if(depth > 0 and tables?, do: [table(depth - 1)], else: [])
    )
  end

  defp table(depth) do
    gen all(
          rows <- list_of(table_row(depth), min_length: 1, max_length: 3),
          extra <- member_of([%{}, %{"colWidths" => [90, 60]}])
        ) do
      "table" |> element(rows) |> Map.merge(extra)
    end
  end

  defp table_row(depth) do
    gen all(cells <- list_of(table_cell(depth), min_length: 1, max_length: 3)) do
      element("tablerow", cells)
    end
  end

  defp table_cell(depth) do
    gen all(
          children <- list_of(block(depth, false), min_length: 1, max_length: 2),
          header_state <- integer(0..3),
          col_span <- integer(1..2),
          background <- member_of([nil, "#ffeeaa"])
        ) do
      "tablecell"
      |> element(children)
      |> Map.merge(%{
        "backgroundColor" => background,
        "colSpan" => col_span,
        "headerState" => header_state,
        "rowSpan" => 1
      })
    end
  end

  defp paragraph do
    gen all(
          children <- inlines(),
          text_format <- integer(0..2047),
          extra <- extra()
        ) do
      "paragraph"
      |> element(children)
      |> Map.merge(%{"textFormat" => text_format, "textStyle" => ""})
      |> Map.merge(extra)
    end
  end

  defp heading do
    gen all(children <- inlines(), tag <- member_of(~w(h1 h2 h3 h4 h5 h6))) do
      "heading" |> element(children) |> Map.put("tag", tag)
    end
  end

  defp quote_block do
    gen all(children <- inlines()) do
      element("quote", children)
    end
  end

  defp code do
    gen all(
          children <- list_of(one_of([code_highlight(), linebreak()]), max_length: 4),
          language <- one_of([constant(nil), member_of(~w(elixir javascript json))])
        ) do
      json = element("code", children)
      if language, do: Map.put(json, "language", language), else: json
    end
  end

  defp list(depth) do
    gen all(
          list_type <- member_of(~w(bullet number check)),
          start <- integer(1..5),
          items <- list_of(list_item(depth, list_type), min_length: 1, max_length: 3)
        ) do
      tag = if list_type == "number", do: "ol", else: "ul"

      "list"
      |> element(items)
      |> Map.merge(%{"listType" => list_type, "start" => start, "tag" => tag})
    end
  end

  defp list_item(depth, list_type) do
    gen all(
          children <- inlines(),
          nested <-
            if(depth > 0, do: list_of(list(depth - 1), max_length: 1), else: constant([])),
          value <- integer(1..9),
          checked <- boolean()
        ) do
      json = "listitem" |> element(children ++ nested) |> Map.put("value", value)
      if list_type == "check", do: Map.put(json, "checked", checked), else: json
    end
  end

  defp inlines do
    list_of(one_of([text(), text(), linebreak(), link(), mention(), unknown()]), max_length: 4)
  end

  @doc "Generates one text node."
  def text do
    gen all(
          text <- string(:printable, max_length: 12),
          format <- integer(0..2047),
          style <- member_of(["", "color: red"]),
          mode <- member_of(~w(normal token segmented))
        ) do
      %{
        "detail" => 0,
        "format" => format,
        "mode" => mode,
        "style" => style,
        "text" => text,
        "type" => "text",
        "version" => 1
      }
    end
  end

  defp code_highlight do
    gen all(
          text <- text(),
          highlight_type <- one_of([constant(nil), member_of(~w(keyword string atom))])
        ) do
      json = Map.put(text, "type", "code-highlight")
      if highlight_type, do: Map.put(json, "highlightType", highlight_type), else: json
    end
  end

  defp linebreak, do: constant(%{"type" => "linebreak", "version" => 1})

  defp link do
    gen all(
          type <- member_of(~w(link autolink)),
          children <- list_of(text(), min_length: 1, max_length: 2),
          url <- member_of(["https://example.com", "mailto:a@example.com"]),
          rel <- one_of([constant(nil), constant("noopener")]),
          target <- one_of([constant(nil), constant("_blank")]),
          title <- one_of([constant(nil), string(:alphanumeric, max_length: 6)]),
          unlinked <- boolean()
        ) do
      json =
        type
        |> element(children)
        |> Map.merge(%{"url" => url, "rel" => rel, "target" => target, "title" => title})

      if type == "autolink", do: Map.put(json, "isUnlinked", unlinked), else: json
    end
  end

  defp mention do
    gen all(
          kind <- member_of(~w(people work)),
          id <- string(:alphanumeric, min_length: 1, max_length: 6),
          label <- string(:printable, min_length: 1, max_length: 10)
        ) do
      decorator_json("mention", %{"kind" => kind, "id" => id, "label" => label})
    end
  end

  defp gallery do
    gen all(attachments <- list_of(attachment(), min_length: 1, max_length: 3)) do
      element("gallery", attachments)
    end
  end

  defp attachment do
    gen all(
          name <- string(:alphanumeric, min_length: 1, max_length: 8),
          image? <- boolean(),
          bytes <- integer(0..100_000),
          width <- integer(1..2000),
          height <- integer(1..2000)
        ) do
      attrs = %{
        "key" => "uploads/#{name}",
        "url" => "/uploads/#{name}",
        "name" => name,
        "contentType" => if(image?, do: "image/png", else: "application/pdf"),
        "bytes" => bytes
      }

      attrs =
        if image?, do: Map.merge(attrs, %{"width" => width, "height" => height}), else: attrs

      decorator_json("attachment", attrs)
    end
  end

  defp unknown do
    gen all(
          suffix <- string(:alphanumeric, min_length: 1, max_length: 6),
          payload <-
            map_of(string(:alphanumeric, min_length: 1, max_length: 4), integer(), max_length: 2)
        ) do
      %{
        "type" => "x-" <> suffix,
        "version" => 1,
        "payload" => payload,
        "children" => [%{"any" => "shape"}]
      }
    end
  end

  defp decorator(type, attrs), do: constant(decorator_json(type, attrs))

  defp decorator_json(type, attrs), do: Map.merge(%{"type" => type, "version" => 1}, attrs)

  defp extra do
    one_of([constant(%{}), constant(%{"$" => %{"state" => "kept"}})])
  end

  defp element(type, children) do
    %{
      "children" => children,
      "direction" => nil,
      "format" => "",
      "indent" => 0,
      "type" => type,
      "version" => 1
    }
  end
end
