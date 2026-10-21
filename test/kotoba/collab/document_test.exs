defmodule Kotoba.Collab.DocumentTest do
  use ExUnit.Case, async: true

  alias Kotoba.Collab.Document
  alias Kotoba.Content

  # The order, receipts and journal are Issho's (Kotoba.CollabTest): here,
  # a transaction is its operations, applied and validated as the
  # authority does.
  defp transaction(_state, operations), do: %{"ops" => operations}

  defp commit(state, transaction, _author, opts \\ []) do
    with {:ok, next} <- Document.apply_ops(state, transaction["ops"]),
         {:ok, content} <- Document.validate(next, opts),
         do: {:ok, next, content, transaction}
  end

  defp state(text \\ "abc"), do: Document.new(Content.from_markdown(text)) |> elem(1)
  defp text(state), do: Document.validate(state) |> elem(1) |> Map.fetch!(:text)

  defp insert(id, after_id, value),
    do: %{
      "op" => "insert_text",
      "id" => "seed:2",
      "after" => after_id,
      "atoms" => [%{"id" => id, "text" => value, "attrs" => %{"type" => "text", "version" => 1}}]
    }

  test "imports server content and exports the existing envelope" do
    {:ok, content} =
      Content.cast(%{
        "type" => "root",
        "children" => [
          %{
            "type" => "paragraph",
            "children" => [
              %{"type" => "text", "text" => "Hello 😀 "},
              %{"type" => "text", "text" => "world", "format" => 1}
            ]
          }
        ]
      })

    {:ok, state} = Document.new(content)
    assert text(state) == "Hello 😀 world"
    assert state["texts"]["seed:2"] |> length() == 13
  end

  test "concurrent offline insertions merge at persistent character anchors" do
    original = state()
    a = transaction(original, [insert("a:1", "seed:2:0", "X")])
    b = transaction(original, [insert("b:1", "seed:2:0", "Y")])
    assert {:ok, accepted, _content, _event} = commit(original, a, "alice")
    assert {:ok, accepted, _content, _event} = commit(accepted, b, "bob")
    assert text(accepted) == "aYXbc"
  end

  test "deletion preserves unseen concurrent insertions and remains an insertion anchor" do
    original = state()

    deletion = %{
      "op" => "text_visibility",
      "id" => "seed:2",
      "atoms" => ["seed:2:1"],
      "deleted" => true,
      "tag" => "alice:delete"
    }

    a = transaction(original, [deletion])
    b = transaction(original, [insert("b:1", "seed:2:1", "😀")])
    {:ok, accepted, _, _} = commit(original, a, "alice")
    {:ok, accepted, _, _} = commit(accepted, b, "bob")
    assert text(accepted) == "a😀c"
  end

  test "concurrent formatting combines independent marks" do
    original = state()

    op = %{
      "op" => "set_text_attrs",
      "id" => "seed:2",
      "atoms" => ["seed:2:0", "seed:2:1", "seed:2:2"]
    }

    a = transaction(original, [Map.put(op, "values", %{"bold" => true})])
    b = transaction(original, [Map.put(op, "values", %{"italic" => true})])
    {:ok, accepted, _, _} = commit(original, a, "alice")
    {:ok, _accepted, content, _} = commit(accepted, b, "bob")
    assert content.html == "<p><strong><em>abc</em></strong></p>"
  end

  test "undo removes only its own deletion and respects another author's formatting" do
    original = state()

    delete = %{
      "op" => "text_visibility",
      "id" => "seed:2",
      "atoms" => ["seed:2:0"],
      "deleted" => true,
      "tag" => "alice:delete"
    }

    {:ok, a, _, _} = commit(original, transaction(original, [delete]), "alice")

    {:ok, b, _, _} =
      commit(a, transaction(a, [Map.put(delete, "tag", "bob:delete")]), "bob")

    {:ok, undone, _, _} =
      commit(b, transaction(b, [Map.put(delete, "deleted", false)]), "alice")

    assert text(undone) == "bc"

    format = %{
      "op" => "set_text_attrs",
      "id" => "seed:2",
      "atoms" => ["seed:2:1"],
      "values" => %{"bold" => true},
      "stamp" => "alice:bold"
    }

    {:ok, a, _, _} = commit(undone, transaction(undone, [format]), "alice")

    {:ok, b, _, _} =
      commit(a, transaction(a, [Map.put(format, "stamp", "bob:bold")]), "bob")

    undo =
      Map.merge(format, %{
        "values" => %{"bold" => false},
        "expected_versions" => %{"bold" => "alice:bold"},
        "stamp" => "alice:undo"
      })

    {:ok, _state, content, _} = commit(b, transaction(b, [undo]), "alice")
    assert content.html == "<p><strong>b</strong>c</p>"
  end

  test "a moved paragraph retains edits from its older offline branch" do
    original = state("abc\n\ndef")
    move = %{"op" => "move_node", "id" => "seed:1", "parent" => "root", "after" => "seed:3"}
    offline = transaction(original, [insert("bob:1", "seed:2:0", "X")])
    {:ok, moved, _, _} = commit(original, transaction(original, [move]), "alice")
    {:ok, merged, _, _} = commit(moved, offline, "bob")
    assert text(merged) == "def\naXbc"
  end

  test "transactions validate atomically, with unsafe URLs and invalid nesting refused" do
    original = state()

    invalid = %{
      "op" => "insert_node",
      "id" => "row",
      "parent" => "root",
      "after" => nil,
      "data" => %{"type" => "tablerow", "version" => 1}
    }

    assert {:error, {:invalid_content, _}} =
             commit(
               original,
               transaction(original, [insert("valid", nil, "X"), invalid]),
               "alice"
             )

    assert text(original) == "abc"

    link = %{
      "op" => "insert_node",
      "id" => "bad-link",
      "parent" => "seed:1",
      "after" => nil,
      "data" => %{"type" => "link", "version" => 1, "url" => "javascript:alert(1)"}
    }

    assert {:error, {:invalid_content, _}} =
             commit(original, transaction(original, [link]), "alice")
  end

  test "features are enforced on accepted content" do
    original = state()

    bold = %{
      "op" => "set_text_attrs",
      "id" => "seed:2",
      "atoms" => ["seed:2:0"],
      "values" => %{"bold" => true}
    }

    assert {:error, {:invalid_content, [:bold]}} =
             commit(original, transaction(original, [bold]), "alice", features: [])
  end

  test "deleted nodes refuse stale operations" do
    original = state()

    delete = %{
      "op" => "node_visibility",
      "id" => "seed:1",
      "deleted" => true,
      "tag" => "alice:delete"
    }

    {:ok, deleted, _, _} = commit(original, transaction(original, [delete]), "alice")

    assert {:error, :deleted_target} =
             commit(deleted, transaction(original, [insert("a:1", nil, "X")]), "bob")
  end

  test "moves cannot form cycles" do
    original = state()
    move = %{"op" => "move_node", "id" => "seed:1", "parent" => "seed:1", "after" => nil}

    assert {:error, :invalid_move} =
             commit(original, transaction(original, [move]), "alice")
  end

  test "offline insertions and formatting follow characters through a paragraph split" do
    original = state()

    split = [
      %{
        "op" => "insert_node",
        "id" => "p2",
        "parent" => "root",
        "after" => "seed:1",
        "data" => %{"type" => "paragraph", "version" => 1}
      },
      %{
        "op" => "insert_node",
        "id" => "text2",
        "parent" => "p2",
        "after" => nil,
        "data" => %{"type" => "text", "version" => 1}
      },
      %{
        "op" => "move_text",
        "id" => "text2",
        "after" => nil,
        "atoms" => ["seed:2:1", "seed:2:2"],
        "stamp" => "alice:split"
      }
    ]

    {:ok, moved, _, _} = commit(original, transaction(original, split), "alice")

    {:ok, merged, _, _} =
      commit(moved, transaction(original, [insert("bob:1", "seed:2:1", "X")]), "bob")

    assert text(merged) == "a\nbXc"

    mark = %{
      "op" => "set_text_attrs",
      "id" => "seed:2",
      "atoms" => ["seed:2:2"],
      "values" => %{"bold" => true},
      "stamp" => "bob:mark"
    }

    {:ok, _merged, content, _} = commit(merged, transaction(original, [mark]), "bob")
    assert content.html == "<p>a</p><p>bX<strong>c</strong></p>"
  end

  test "malformed attributes and deep JSON fail without changing the accepted state" do
    original = state()
    base = %{"op" => "set_text_attrs", "id" => "seed:2", "atoms" => ["seed:2:0"]}

    for values <- [
          %{"bold" => "yes"},
          %{"type" => "paragraph"},
          %{"children" => []},
          %{"__proto__" => %{}}
        ] do
      assert {:error, _} =
               commit(
                 original,
                 transaction(original, [Map.put(base, "values", values)]),
                 "alice"
               )
    end

    nested = Enum.reduce(1..50, nil, fn _, value -> %{"nested" => value} end)

    assert {:error, _} =
             commit(
               original,
               transaction(original, [Map.put(base, "values", %{"style" => nested})]),
               "alice"
             )

    assert text(original) == "abc"
  end

  test "undoing a created container preserves concurrent text" do
    original = state()

    inverse = %{
      "op" => "node_visibility",
      "id" => "seed:2",
      "deleted" => true,
      "tag" => "alice:undo",
      "if_empty" => true
    }

    {:ok, unchanged, _, _} = commit(original, transaction(original, [inverse]), "alice")
    assert text(unchanged) == "abc"

    delete = %{
      "op" => "text_visibility",
      "id" => "seed:2",
      "atoms" => ~w(seed:2:0 seed:2:1 seed:2:2),
      "deleted" => true,
      "tag" => "alice:delete"
    }

    {:ok, empty, _, _} =
      commit(unchanged, transaction(unchanged, [delete, inverse]), "alice")

    assert empty["nodes"]["seed:2"]["deleted"]
  end

  test "malformed operations do not crash the authority" do
    original = state()

    for op <- [
          nil,
          %{},
          %{"op" => "insert_text", "id" => "seed:2", "after" => nil, "atoms" => [nil]}
        ] do
      assert {:error, _} = commit(original, transaction(original, [op]), "alice")
    end
  end

  test "reserved dictionary IDs and duplicate text moves are rejected" do
    original = state()

    for id <- ~w(__proto__ constructor toString) do
      operation = %{
        "op" => "insert_node",
        "id" => id,
        "parent" => "root",
        "after" => nil,
        "data" => %{"type" => "paragraph"}
      }

      assert {:error, _} = commit(original, transaction(original, [operation]), "alice")
    end

    move = %{
      "op" => "move_text",
      "id" => "seed:2",
      "atoms" => ["seed:2:0", "seed:2:0"],
      "after" => nil,
      "stamp" => "move"
    }

    assert {:error, _} = commit(original, transaction(original, [move]), "alice")
  end
end
