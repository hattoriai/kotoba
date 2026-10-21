if Code.ensure_loaded?(Issho.Binding) do
  defmodule Kotoba.Issho.Engine do
    @moduledoc false
    # The document's state and operations: Kotoba.Collab.Document. Issho
    # keeps the epoch, revision, receipts and journal around it.
    @behaviour Issho.Engine

    alias Kotoba.Collab.Document

    @impl true
    def name, do: "kotoba"

    @impl true
    def version, do: 1

    @impl true
    def init(content, opts), do: Document.new(content, policy(opts))

    @impl true
    def apply(state, ops, _opts), do: Document.apply_ops(state, ops)

    @impl true
    def validate(state, opts), do: Document.validate(state, policy(opts))

    @impl true
    def upgrade(stored), do: Document.upgrade(stored)

    defp policy(opts), do: Keyword.drop(opts, [:author])
  end

  defmodule Kotoba.Issho.Place do
    @moduledoc false
    # A selection: an anchor and a focus, each a node and the character
    # before the caret (and an offset in a node with no characters).
    @behaviour Issho.Place

    @impl true
    def validate(nil), do: :ok

    def validate(%{"anchor" => anchor, "focus" => focus}) do
      if point?(anchor) and point?(focus), do: :ok, else: {:error, :invalid_selection}
    end

    def validate(_other), do: {:error, :invalid_selection}

    defp point?(%{"node" => node, "before" => before} = point),
      do:
        id?(node) and (is_nil(before) or id?(before)) and
          (not Map.has_key?(point, "offset") or
             (is_integer(point["offset"]) and point["offset"] >= 0))

    defp point?(_other), do: false

    defp id?(value), do: is_binary(value) and byte_size(value) <= 160
  end

  defmodule Kotoba.Issho.Store do
    @moduledoc false
    # An Issho store on the app's Kotoba.Collab.Store: the same rows, and
    # the content the app has for a document no one has edited together.
    @behaviour Issho.Store

    @impl true
    def load({store, context}, id) do
      case store.load(context, id) do
        {:ok, %{state: nil, content: content}} -> {:ok, {:initial, content}}
        {:ok, %{state: state}} -> {:ok, state}
        {:error, _reason} = error -> error
      end
    end

    @impl true
    def save({store, context}, id, expected, document, content),
      do: store.save(context, id, expected, document, content)
  end

  defmodule Kotoba.Issho do
    @moduledoc """
    Kotoba's binding for [Issho](https://hex.pm/packages/issho): a shared
    editor's document is an Issho document, its engine Kotoba's semantic
    operations (`Kotoba.Collab.Document`), and a person's place their
    selection in it.

    Name it as a document's engine through `Kotoba.Collab.document/1`.
    """

    use Issho.Binding, engine: Kotoba.Issho.Engine, place: Kotoba.Issho.Place

    @doc ~S"""
    Kotoba's tools for agents (`Issho.Tool`): an agent reads a shared
    document, selects text (the people see its selection), types (they see
    it written), replaces, deletes, formats, links, adds blocks, copies
    and pastes, as a person does in the editor, and its changes merge with
    theirs. Give them to your app's model (`Issho.Tools`), or serve them to
    MCP clients (`Issho.MCP`), with Issho's room tools:

        tools = Issho.Tools.room() ++ Kotoba.Issho.tools()

    A tool names its document by id (`"notebook:7/intro"`); the room is the
    part before the `"/"`. Text is quoted, not counted: `select_text` with
    the words, then `link_text` with no text links the selection.
    """
    @spec tools() :: [module()]
    def tools,
      do: [
        Kotoba.Issho.Tools.Read,
        Kotoba.Issho.Tools.Select,
        Kotoba.Issho.Tools.Type,
        Kotoba.Issho.Tools.Replace,
        Kotoba.Issho.Tools.Delete,
        Kotoba.Issho.Tools.Format,
        Kotoba.Issho.Tools.Link,
        Kotoba.Issho.Tools.AddBlock,
        Kotoba.Issho.Tools.Copy,
        Kotoba.Issho.Tools.Paste
      ]
  end
end
