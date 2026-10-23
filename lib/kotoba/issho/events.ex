defmodule Kotoba.Issho.Events do
  @moduledoc false
  # The events of a shared document's change (`Kotoba.Issho.events/2`): the
  # blocks it added and removed, and the blocks whose text it changed, from
  # the state before and after it. Only what the change touched is read
  # again: the texts and nodes that are not the same terms as before.

  alias Kotoba.Issho.Text

  @doc false
  def events(_ops, %{before: before, after: after_state}) do
    was = Text.outline(before)
    now = Text.outline(after_state)
    was_ids = MapSet.new(was, & &1.id)
    now_ids = MapSet.new(now, & &1.id)

    added = for block <- now, block.id not in was_ids, do: {"text.block_added", data(block)}

    removed =
      for block <- was,
          block.id not in now_ids,
          do: {"text.block_removed", %{block: block.id, type: Text.kind(block)}}

    touched = touched(before, after_state)

    changed =
      for block <- now,
          block.id in was_ids and block.id in touched,
          Text.block_text(before, block.id) != Text.block_text(after_state, block.id),
          do: {"text.changed", data(block)}

    added ++ removed ++ changed
  end

  defp data(block), do: %{block: block.id, type: Text.kind(block), n: block.n}

  # The blocks a change may have changed the text of: those of the texts and
  # the nodes it changed.
  defp touched(before, after_state) do
    texts = for {id, atoms} <- after_state["texts"], before["texts"][id] !== atoms, do: id
    nodes = for {id, node} <- after_state["nodes"], before["nodes"][id] !== node, do: id

    (texts ++ nodes)
    |> Enum.map(&Text.block_of(after_state, &1))
    |> MapSet.new()
  end
end
