defmodule Kotoba.Issho.EventsTest do
  use ExUnit.Case, async: false

  alias Kotoba.Collab.{Document, Store}
  alias Kotoba.Content
  alias Kotoba.Issho.Text

  defmodule Policy do
    @moduledoc false
    @behaviour Issho.Policy

    @impl true
    def authorize(_identity, _document_id, _action), do: :ok

    @impl true
    def document(_identity, "quiet:" <> _),
      do: Kotoba.Issho.document(store: {Store.Memory, :kotoba_events_store}, events: false)

    def document(_identity, _document_id),
      do: Kotoba.Issho.document(store: {Store.Memory, :kotoba_events_store})
  end

  defp state(markdown) do
    {:ok, state} = Document.new(Content.from_markdown(markdown))
    state
  end

  # The events of operations on a state, and the state after them.
  defp events(state, ops) do
    {:ok, next} = Document.apply_ops(state, ops)
    {Kotoba.Issho.events(ops, %{before: state, after: next}), next}
  end

  defp id(state, n), do: Enum.find(Text.outline(state), &(&1.n == n)).id

  test "typing in a block changes its text" do
    state = state("First\n\nSecond")
    {:ok, range} = Text.find(state, "Second")
    {:ok, ops, _next, _caret} = Text.insert(state, %{block: range.block, index: 6}, " line")

    second = id(state, 2)

    assert {[{"text.changed", %{block: ^second, type: "paragraph", n: 2}}], _} =
             events(state, ops)
  end

  test "a deletion changes the text; a change of format does not" do
    state = state("First\n\n## Second words")
    {:ok, range} = Text.find(state, "words")
    {:ok, ops, _next} = Text.delete(state, range)
    assert {[{"text.changed", %{type: "h2", n: 2}}], _} = events(state, ops)

    {:ok, ops, _next} = Text.format(state, range, %{"bold" => true})
    assert {[], _} = events(state, ops)
  end

  test "a block added, removed, and back with an undo" do
    state = state("First")
    {:ok, ops, _next, _caret} = Text.insert_block(state, 1, "quote", "Said")
    {[{"text.block_added", %{block: block, type: "quote", n: 2}}], state} = events(state, ops)

    remove = [%{"op" => "node_visibility", "id" => block, "deleted" => true, "tag" => "t1"}]

    assert {[{"text.block_removed", %{block: ^block, type: "quote"}}], gone} =
             events(state, remove)

    undo = [%{"op" => "node_visibility", "id" => block, "deleted" => false, "tag" => "t1"}]
    assert {[{"text.block_added", %{block: ^block, n: 2}}], _} = events(gone, undo)
  end

  test "a list's items are blocks, numbered as read_text numbers them" do
    state = state("Intro\n\n- one\n- two")
    {:ok, range} = Text.find(state, "two")
    {:ok, ops, _next, _caret} = Text.insert(state, %{block: range.block, index: 3}, "!")

    assert {[{"text.changed", %{type: "bullet item", n: 3}}], _} = events(state, ops)
  end

  describe "in the room" do
    setup do
      start_supervised!({Store.Memory, name: :kotoba_events_store})
      %{instance: Issho.Test.start!(policy: Policy)}
    end

    test "a saved change is an event of the room, with its document and author", %{
      instance: instance
    } do
      document = "notebook:#{System.unique_integer([:positive])}/intro"
      :ok = Store.Memory.seed(:kotoba_events_store, document, Content.from_markdown("Hello"))
      :ok = Issho.Events.subscribe(instance, Issho.Policy.room(document))

      state = state("Hello")
      {:ok, range} = Text.find(state, "Hello")
      {:ok, ops, _next, _caret} = Text.insert(state, %{block: range.block, index: 5}, "!")
      {:ok, _receipt} = Kotoba.Issho.change(instance, document, ops, author: "importer")

      assert_receive {Issho, :event,
                      %Issho.Event{
                        name: "text.changed",
                        document: ^document,
                        data: %{type: "paragraph", n: 1}
                      } = event}

      assert event.by.key == "importer"
    end

    test "a document with events: false has none of Kotoba's", %{instance: instance} do
      document = "quiet:#{System.unique_integer([:positive])}"
      :ok = Store.Memory.seed(:kotoba_events_store, document, Content.from_markdown("Hello"))
      :ok = Issho.Events.subscribe(instance, Issho.Policy.room(document))

      state = state("Hello")
      {:ok, range} = Text.find(state, "Hello")
      {:ok, ops, _next, _caret} = Text.insert(state, %{block: range.block, index: 5}, "!")
      {:ok, _receipt} = Kotoba.Issho.change(instance, document, ops)

      assert_receive {Issho, :event, %Issho.Event{name: "document.changed"}}
      refute_received {Issho, :event, %Issho.Event{name: "text." <> _}}
    end
  end
end
