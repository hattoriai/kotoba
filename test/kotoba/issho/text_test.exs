defmodule Kotoba.Issho.TextTest do
  use ExUnit.Case, async: true

  alias Kotoba.Collab.Document
  alias Kotoba.Content
  alias Kotoba.Issho.Text

  defp state(markdown) do
    {:ok, state} = Document.new(Content.from_markdown(markdown))
    state
  end

  defp html(state) do
    {:ok, content} = Document.validate(state)
    content.html
  end

  # The operations alone give the same state: they are what the authority applies.
  defp replayed(state, ops) do
    {:ok, next} = Document.apply_ops(state, ops)
    next
  end

  test "reads the blocks, numbered, with their kinds and links" do
    state = state("# Plan\n\nHello **bold** [link](https://x.io) end\n\n- one\n- two")

    assert Text.read(state) == [
             %{"n" => 1, "type" => "h1", "text" => "Plan"},
             %{
               "n" => 2,
               "type" => "paragraph",
               "text" => "Hello bold link end",
               "links" => [%{"text" => "link", "url" => "https://x.io"}]
             },
             %{"n" => 3, "type" => "bullet item", "text" => "one"},
             %{"n" => 4, "type" => "bullet item", "text" => "two"}
           ]
  end

  test "finds a quote, its nth occurrence, or in one block" do
    state = state("one two one\n\nthe one")
    assert {:ok, %{from: 0, to: 3, block: %{n: 1}}} = Text.find(state, "one")
    assert {:ok, %{from: 8, block: %{n: 1}}} = Text.find(state, "one", occurrence: 2)
    assert {:ok, %{from: 4, block: %{n: 2}}} = Text.find(state, "one", block: 2)
    assert {:error, "\"one\" occurs 3 time(s)."} = Text.find(state, "one", occurrence: 4)
    assert {:error, _} = Text.find(state, "three")
  end

  test "a range is a selection the editors draw, and back" do
    state = state("Hello world")
    {:ok, range} = Text.find(state, "world")
    place = Text.place(range)
    assert %{"anchor" => %{"before" => before}, "focus" => %{"before" => last}} = place
    assert before != nil and last != nil
    assert {:ok, %{from: 6, to: 11}} = Text.from_place(state, place)
  end

  test "types text after a quote, with its formatting, and new lines make blocks" do
    state = state("Hello **bold** end")
    {:ok, range} = Text.find(state, "bold")

    {:ok, ops, next, caret} = Text.insert(state, %{block: range.block, index: range.to}, "er")
    assert html(next) == "<p>Hello <strong>bolder</strong> end</p>"
    assert replayed(state, ops) == next

    {:ok, _ops, next, _caret} = Text.insert(next, Text.caret_in(next, caret), " text\nA new line")

    assert html(next) ==
             "<p>Hello <strong>bolder text</strong></p><p><strong>A new line</strong> end</p>"
  end

  test "types into an empty document, and at the end of a link, after it" do
    {:ok, empty} = Document.new(nil)
    {:ok, caret} = Text.caret(empty, :end)
    {:ok, _ops, next, _} = Text.insert(empty, caret, "First words")
    assert html(next) == "<p>First words</p>"

    state = state("See [docs](https://x.io)")
    {:ok, caret} = Text.caret(state, {:end, 1})
    {:ok, _ops, next, _} = Text.insert(state, caret, " now")
    assert html(next) =~ ~s(<a href="https://x.io" rel="noopener nofollow">docs</a> now</p>)
  end

  test "deletes, replaces and formats a range" do
    state = state("The quick brown fox")
    {:ok, range} = Text.find(state, "quick ")
    {:ok, ops, next} = Text.delete(state, range)
    assert html(next) == "<p>The brown fox</p>"
    assert replayed(state, ops) == next

    {:ok, range} = Text.find(next, "brown")
    {:ok, _ops, next} = Text.format(next, range, %{"bold" => true, "italic" => true})
    assert html(next) == "<p>The <strong><em>brown</em></strong> fox</p>"
  end

  test "makes a range a link, as the editor's link command does" do
    state = state("Read the docs today")
    {:ok, range} = Text.find(state, "the docs")
    {:ok, ops, next} = Text.link(state, range, "https://kotoba.dev")

    assert html(next) ==
             ~s(<p>Read <a href="https://kotoba.dev" rel="noopener nofollow">the docs</a> today</p>)

    assert replayed(state, ops) == next

    assert [%{"links" => [%{"text" => "the docs", "url" => "https://kotoba.dev"}]}] =
             Text.read(next)

    {:ok, range} = Text.find(next, "docs today")

    assert {:error, "Part of that text is a link already."} =
             Text.link(next, range, "https://x.io")
  end

  test "adds a block after another, or first" do
    state = state("One\n\nThree")
    {:ok, _ops, next, _} = Text.insert_block(state, 1, "paragraph", "Two")
    {:ok, _ops, next, _} = Text.insert_block(next, 0, "h2", "Title")
    assert html(next) == "<h2>Title</h2><p>One</p><p>Two</p><p>Three</p>"
    assert {:error, _} = Text.insert_block(next, 9, "paragraph", "x")
  end
end
