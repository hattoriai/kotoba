defmodule Kotoba.Collab.CompactTest do
  # Document.compact/1 drops what only past operations need (deleted
  # characters, the copies characters were moved from, deleted nodes) and
  # keeps every node and character that remains as it was, so places and
  # comments that name them stay on the same words.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Kotoba.Collab.Document
  alias Kotoba.Content

  defp state(markdown), do: Document.new(Content.from_markdown(markdown)) |> elem(1)

  defp apply!(state, ops) do
    {:ok, next} = Document.apply_ops(state, ops)
    next
  end

  defp content(state) do
    {:ok, content} = Document.validate(state)
    content
  end

  defp delete_text(buffer, ids, tag \\ "ada:delete"),
    do: %{
      "op" => "text_visibility",
      "id" => buffer,
      "atoms" => ids,
      "deleted" => true,
      "tag" => tag
    }

  defp delete_node(id, tag \\ "ada:delete"),
    do: %{"op" => "node_visibility", "id" => id, "deleted" => true, "tag" => tag}

  defp insert(buffer, after_id, id, text),
    do: %{
      "op" => "insert_text",
      "id" => buffer,
      "after" => after_id,
      "atoms" => [%{"id" => id, "text" => text, "attrs" => %{"type" => "text", "version" => 1}}]
    }

  # "abc" and "def": a paragraph split moves "c" to a new paragraph, "b"
  # is deleted, and the second paragraph goes.
  defp edited do
    state("abc\n\ndef")
    |> apply!([
      %{
        "op" => "insert_node",
        "id" => "p2",
        "parent" => "root",
        "after" => "seed:1",
        "data" => %{"type" => "paragraph", "version" => 1}
      },
      %{
        "op" => "insert_node",
        "id" => "t2",
        "parent" => "p2",
        "after" => nil,
        "data" => %{"type" => "text", "version" => 1}
      },
      %{
        "op" => "move_text",
        "id" => "t2",
        "after" => nil,
        "atoms" => ["seed:2:2"],
        "stamp" => "ada:split"
      }
    ])
    |> apply!([delete_text("seed:2", ["seed:2:1"]), delete_node("seed:3")])
  end

  test "keeps the content and every remaining node and character as it was, and nothing else" do
    before = edited()
    {:ok, compacted} = Document.compact(before)

    assert content(compacted) == content(before)
    assert content(compacted).text == "a\nc"

    assert Map.keys(compacted["nodes"]) |> Enum.sort() ==
             ["p2", "root", "seed:1", "seed:2", "t2"]

    for {id, node} <- compacted["nodes"], do: assert(node == before["nodes"][id])
    assert compacted["texts"]["seed:2"] == Enum.take(before["texts"]["seed:2"], 1)
    assert compacted["texts"]["t2"] == before["texts"]["t2"]
    assert compacted["orders"]["root"] == ["seed:1", "p2"]
    refute Map.has_key?(compacted["texts"], "seed:4")
  end

  test "compacting twice is compacting once" do
    {:ok, once} = Document.compact(edited())
    assert Document.compact(once) == {:ok, once}
  end

  test "an operation that names what compaction dropped is refused, never applied elsewhere" do
    {:ok, compacted} = Document.compact(edited())

    for {op, reason} <- [
          {Map.put(delete_text("seed:2", ["seed:2:1"]), "deleted", false), :unknown_atom},
          {insert("seed:2", "seed:2:1", "x:1", "X"), :unknown_anchor},
          {%{
             "op" => "set_text_attrs",
             "id" => "seed:2",
             "atoms" => ["seed:2:1"],
             "values" => %{"bold" => true}
           }, :unknown_atom},
          {%{
             "op" => "move_text",
             "id" => "t2",
             "after" => nil,
             "atoms" => ["seed:2:1"],
             "stamp" => "ada:move"
           }, :unknown_atom},
          {Map.put(delete_node("seed:3"), "deleted", false), :unknown_node},
          {insert("seed:4", nil, "x:2", "X"), :unknown_node},
          {%{
             "op" => "insert_node",
             "id" => "p3",
             "parent" => "root",
             "after" => "seed:3",
             "data" => %{"type" => "paragraph", "version" => 1}
           }, :unknown_anchor}
        ] do
      assert Document.apply_ops(compacted, [op]) == {:error, reason}
    end
  end

  test "an operation on what remains applies as it would have" do
    before = edited()
    {:ok, compacted} = Document.compact(before)
    ops = [insert("seed:2", "seed:2:0", "x:1", "X"), insert("t2", "seed:2:2", "x:2", "Y")]

    assert content(apply!(compacted, ops)) == content(apply!(before, ops))
    assert content(apply!(compacted, ops)).text == "aX\ncY"
  end

  # An editor's view: the live blocks, text nodes and characters, which is
  # all Kotoba's binding names in what it sends.
  defp children(state, id) do
    Enum.filter(state["orders"][id] || [], fn child ->
      state["nodes"][child]["parent"] == id and not state["nodes"][child]["deleted"]
    end)
  end

  defp buffers(state, id \\ "root") do
    Enum.flat_map(children(state, id), fn child ->
      if Map.has_key?(state["texts"], child), do: [child], else: buffers(state, child)
    end)
  end

  defp visible(state, buffer),
    do: Enum.reject(state["texts"][buffer], &(&1["deleted"] or &1["moved_to"]))

  @attrs %{"type" => "text", "version" => 1}

  defp intent do
    index = non_negative_integer()

    frequency([
      {5,
       tuple({constant(:type), index, index, string(:alphanumeric, min_length: 1, max_length: 6)})},
      {4, tuple({constant(:delete), index, index, integer(1..8)})},
      {2, tuple({constant(:format), index, index, integer(1..6), member_of(~w(bold italic))})},
      {2, tuple({constant(:split), index, index})},
      {1,
       tuple({constant(:paragraph), index, string(:alphanumeric, min_length: 1, max_length: 6)})},
      {1, tuple({constant(:delete_block), index})},
      {1, tuple({constant(:move_block), index, index})}
    ])
  end

  # The operations an editor sends for an intent, on what it sees of the
  # state, with ids made from `n`.
  defp edit(state, {:type, b, p, text}, n) do
    with_buffer(state, b, fn buffer, atoms ->
      at = rem(p, length(atoms) + 1)
      before = if at > 0, do: Enum.at(atoms, at - 1)
      anchor = before || List.first(atoms)

      inserted =
        text
        |> String.codepoints()
        |> Enum.with_index()
        |> Enum.map(fn {char, i} ->
          %{
            "id" => "n#{n}:#{i}",
            "text" => char,
            "attrs" => (anchor && anchor["attrs"]) || @attrs
          }
        end)

      op = %{
        "op" => "insert_text",
        "id" => buffer,
        "after" => before && before["id"],
        "atoms" => inserted
      }

      op =
        if anchor,
          do: Map.merge(op, %{"inherit" => anchor["id"], "base_attrs" => anchor["attrs"]}),
          else: op

      [op]
    end)
  end

  defp edit(state, {:delete, b, p, count}, n) do
    with_range(state, b, p, count, fn buffer, ids -> [delete_text(buffer, ids, "n#{n}")] end)
  end

  defp edit(state, {:format, b, p, count, mark}, n) do
    with_range(state, b, p, count, fn buffer, ids ->
      [
        %{
          "op" => "set_text_attrs",
          "id" => buffer,
          "atoms" => ids,
          "values" => %{mark => true},
          "stamp" => "n#{n}"
        }
      ]
    end)
  end

  defp edit(state, {:split, b, p}, n) do
    with_buffer(state, b, fn buffer, atoms ->
      paragraph = state["nodes"][buffer]["parent"]
      moved = atoms |> Enum.drop(rem(p, length(atoms) + 1)) |> Enum.map(& &1["id"])

      [
        %{
          "op" => "insert_node",
          "id" => "p#{n}",
          "parent" => state["nodes"][paragraph]["parent"],
          "after" => paragraph,
          "data" => state["nodes"][paragraph]["data"]
        },
        %{
          "op" => "insert_node",
          "id" => "t#{n}",
          "parent" => "p#{n}",
          "after" => nil,
          "data" => %{"type" => "text", "version" => 1}
        }
      ] ++
        if moved == [],
          do: [],
          else: [
            %{
              "op" => "move_text",
              "id" => "t#{n}",
              "after" => nil,
              "atoms" => moved,
              "stamp" => "n#{n}"
            }
          ]
    end)
  end

  defp edit(state, {:paragraph, i, text}, n) do
    blocks = children(state, "root")

    [
      %{
        "op" => "insert_node",
        "id" => "p#{n}",
        "parent" => "root",
        "after" => if(blocks != [], do: Enum.at(blocks, rem(i, length(blocks)))),
        "data" => %{"type" => "paragraph", "version" => 1}
      },
      %{
        "op" => "insert_node",
        "id" => "t#{n}",
        "parent" => "p#{n}",
        "after" => nil,
        "data" => %{"type" => "text", "version" => 1}
      },
      %{
        "op" => "insert_text",
        "id" => "t#{n}",
        "after" => nil,
        "atoms" => [%{"id" => "n#{n}:0", "text" => text, "attrs" => @attrs}]
      }
    ]
  end

  defp edit(state, {:delete_block, i}, n) do
    case children(state, "root") do
      [_one] -> []
      blocks -> [delete_node(Enum.at(blocks, rem(i, length(blocks))), "n#{n}")]
    end
  end

  defp edit(state, {:move_block, i, j}, n) do
    blocks = children(state, "root")
    moving = Enum.at(blocks, rem(i, length(blocks)))
    others = [nil | blocks -- [moving]]

    [
      %{
        "op" => "move_node",
        "id" => moving,
        "parent" => "root",
        "after" => Enum.at(others, rem(j, length(others))),
        "stamp" => "n#{n}"
      }
    ]
  end

  defp with_buffer(state, b, fun) do
    case buffers(state) do
      [] ->
        []

      buffers ->
        buffer = Enum.at(buffers, rem(b, length(buffers)))
        fun.(buffer, visible(state, buffer))
    end
  end

  defp with_range(state, b, p, count, fun) do
    with_buffer(state, b, fn
      _buffer, [] ->
        []

      buffer, atoms ->
        ids =
          atoms |> Enum.drop(rem(p, length(atoms))) |> Enum.take(count) |> Enum.map(& &1["id"])

        fun.(buffer, ids)
    end)
  end

  # The state after each intent's operations, those that apply.
  defp run(state, intents) do
    intents
    |> Enum.with_index()
    |> Enum.reduce(state, fn {intent, n}, state ->
      ops = edit(state, intent, n)

      case ops != [] && Document.apply_ops(state, ops) do
        {:ok, next} -> next
        _skipped -> state
      end
    end)
  end

  defp live_nodes(state, id \\ "root"),
    do: [id | Enum.flat_map(children(state, id), &live_nodes(state, &1))]

  property "a compacted state takes the same later edits as the state it came from, to the same content" do
    check all(
            start <- member_of(["abc def", "one\n\ntwo three\n\nfour"]),
            earlier <- list_of(intent(), max_length: 40),
            later <- list_of(intent(), max_length: 30),
            max_runs: 150
          ) do
      full = run(state(start), earlier)
      {:ok, compacted} = Document.compact(full)
      assert content(compacted) == content(full)

      {:ok, final} =
        later
        |> Enum.with_index(1_000)
        |> Enum.reduce({:ok, {full, compacted}}, fn {intent, n}, {:ok, {full, compacted}} ->
          ops = edit(full, intent, n)
          result = if ops == [], do: {:ok, full}, else: Document.apply_ops(full, ops)
          also = if ops == [], do: {:ok, compacted}, else: Document.apply_ops(compacted, ops)

          case {result, also} do
            {{:ok, full}, {:ok, compacted}} ->
              assert content(compacted) == content(full)
              {:ok, {full, compacted}}

            {{:error, _}, {:error, _}} ->
              {:ok, {full, compacted}}

            different ->
              flunk("#{inspect(ops)} gave #{inspect(different, limit: 5)}")
          end
        end)

      {full, compacted} = final
      assert content(compacted) == content(full)
      assert Document.compact(compacted) == Document.compact(full)
    end
  end

  property "compacting twice is compacting once, and keeps each remaining node and character" do
    check all(
            start <- member_of(["abc def", "one\n\ntwo three\n\nfour"]),
            intents <- list_of(intent(), max_length: 40),
            max_runs: 150
          ) do
      full = run(state(start), intents)
      {:ok, once} = Document.compact(full)
      assert Document.compact(once) == {:ok, once}

      live = buffers(full)
      assert buffers(once) == live

      for buffer <- live, do: assert(once["texts"][buffer] == visible(full, buffer))

      assert Enum.sort(Map.keys(once["nodes"])) == Enum.sort(live_nodes(full))
      for {id, node} <- once["nodes"], do: assert(node == full["nodes"][id])
    end
  end
end
