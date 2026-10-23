if Code.ensure_loaded?(Issho.Live) do
  defmodule Kotoba.Issho.Comments do
    @moduledoc false
    # A Kotoba editor as the composer of Issho's comments
    # (Issho.Components.comments/1's :input slot and :read): see
    # Kotoba.Issho.comment_prompts/2, comment_field/3 and read_comment/1.
    #
    # A comment keeps its words as text, and whom it mentions as keys. In
    # the editor, a mention of the room's people (and of `mentionable`) is
    # a mention node of kind "people", whose id is the person's key; in the
    # comment, it is "@" and their name, as Issho's own composer writes it.

    alias Kotoba.{Content, Document, Prompts}
    alias Kotoba.Nodes.Mention

    @kind "people"

    def prompts(room, mentionable) do
      search = fn query -> Prompts.filter(people(room, mentionable), query) end
      [{"@", :people, [search: search, spaces: true, label: "People"]}]
    end

    # The comment's words as a document, for the editor that edits it:
    # a paragraph for each line, and a mention for each "@" and name of
    # someone it may mention.
    def field(%{field: field, value: value}, room, mentionable) do
      names =
        room
        |> people(mentionable)
        |> Enum.uniq_by(& &1.label)
        |> Enum.sort_by(&(-String.length(&1.label)))

      %{field | value: content(value || "", names)}
    end

    def read(%{"body" => json}) when is_binary(json) do
      with {:ok, %Content{doc: doc}} <- Content.cast(json),
           {:ok, document} <- Document.parse(doc) do
        mentions = for %Mention{kind: @kind, id: id} <- Document.mentions(document), do: id

        body =
          document
          |> Document.map(fn
            %Mention{kind: @kind, label: label} = mention -> %{mention | label: "@" <> label}
            node -> node
          end)
          |> Document.text()
          |> String.trim()

        %{body: body, mentions: Enum.uniq(mentions)}
      else
        _invalid -> %{body: "", mentions: []}
      end
    end

    def read(_params), do: %{body: "", mentions: []}

    # The people a comment may mention: the room's, here first, and
    # `mentionable`, once each.
    defp people(room, mentionable) do
      here =
        for {key, %{metas: [meta | _]}} <- Issho.Live.people(room),
            is_binary(meta["name"]),
            do: %{id: key, label: meta["name"], hint: "Here"}

      given =
        for person <- mentionable,
            key = person[:key] || person["key"],
            name = person[:name] || person["name"],
            do: %{id: to_string(key), label: to_string(name)}

      Enum.uniq_by(here ++ given, & &1.id)
    end

    defp content(text, names) do
      paragraphs =
        for line <- String.split(text, "\n"),
            do: %{
              "type" => "paragraph",
              "version" => 1,
              "children" => line |> split(names) |> Enum.map(&inline/1)
            }

      %{
        "kotoba" => 1,
        "lexical" => "0.51",
        "root" => %{"type" => "root", "version" => 1, "children" => paragraphs}
      }
    end

    # A line in pieces: text, and the "@Name" of each person.
    defp split("", _names), do: []
    defp split(line, []), do: [line]

    defp split(line, names) do
      pattern =
        names
        |> Enum.map_join("|", &Regex.escape("@" <> &1.label))
        |> Regex.compile!("u")

      by_name = Map.new(names, &{"@" <> &1.label, &1})

      pattern
      |> Regex.split(line, include_captures: true, trim: true)
      |> Enum.map(&Map.get(by_name, &1, &1))
    end

    defp inline(%{id: id, label: label}),
      do: %{"type" => "mention", "version" => 1, "kind" => @kind, "id" => id, "label" => label}

    defp inline(text),
      do: %{
        "type" => "text",
        "version" => 1,
        "text" => text,
        "format" => 0,
        "detail" => 0,
        "mode" => "normal",
        "style" => ""
      }
  end
end
