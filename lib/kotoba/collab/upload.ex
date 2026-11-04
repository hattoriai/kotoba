if Code.ensure_loaded?(Issho) do
  defmodule Kotoba.Collab.Upload do
    @moduledoc false
    # A person's upload in a shared editor, put in the shared document by the
    # server (`Kotoba.Live.consume_uploads/4` with `:issho`), in the same step
    # that stored its file, as an agent's attach_file does. The browser only
    # says where its marker was: an upload is in the document even when the
    # browser could not share it, and a file no document points to is
    # removed.
    #
    # The place (the file's meta, from the editor): `"parent"`, the shared id
    # of a gallery the marker is in (`nil`: the document); `"after"`, the
    # node it goes after (the top-level block that holds the marker, or the
    # gallery item before it); `"first"`, first in its parent; and
    # `"batch"` and `"index"`, the files handed in together and their order.

    alias Kotoba.Collab.Document
    alias Kotoba.Nodes.Attachment

    @doc false
    # The place a shared editor gave for an upload entry, or nil.
    def place(%{"kotoba" => %{} = place}), do: place
    def place(_meta), do: nil

    @doc false
    # Puts the attachment `node` in the shared document of `issho`
    # (`:instance`, `:document`, and `:author`), at `place`, after the files
    # of its batch that are already in (`placed`: index => shared id).
    # Gives the shared id of the new node.
    def insert(issho, %Attachment{} = node, %{} = place, placed \\ %{}) do
      instance = Keyword.fetch!(issho, :instance)
      document = Keyword.fetch!(issho, :document)

      with {:ok, pid} <- Issho.Documents.open(instance, document),
           {:ok, %{"state" => state}} <- Issho.Authority.snapshot(pid) do
        parent = parent(state, place["parent"])
        # The gallery is gone: the place in it is too, the file goes at the end.
        place = if parent == (place["parent"] || state["root"]), do: place, else: %{}
        id = Document.random_id()

        op = %{
          "op" => "insert_node",
          "id" => id,
          "parent" => parent,
          "after" => after_id(state, parent, place, placed),
          "data" => node |> Attachment.to_json() |> Map.put_new("version", 1),
          "element" => false
        }

        opts = if author = issho[:author], do: [author: author], else: []

        case Kotoba.Issho.change(instance, document, [op], opts) do
          {:ok, _receipt} -> {:ok, id}
          {:error, reason} -> {:error, reason}
        end
      end
    end

    # The gallery of the marker while it is in the document, else the root.
    defp parent(state, id) when is_binary(id) do
      if reachable?(state, id), do: id, else: state["root"]
    end

    defp parent(state, _id), do: state["root"]

    # After the last file of its batch that comes before it, so that files
    # handed in together keep their order whichever finishes first; else
    # where the marker was; else, when that is gone, at the end.
    defp after_id(state, parent, place, placed) do
      index = place["index"]

      before =
        placed
        |> Enum.filter(fn {other, id} ->
          is_integer(index) and other < index and child?(state, parent, id)
        end)
        |> Enum.max_by(fn {other, _id} -> other end, fn -> nil end)

      cond do
        before != nil -> elem(before, 1)
        place["first"] == true -> nil
        child?(state, parent, place["after"]) -> place["after"]
        true -> last_child(state, parent)
      end
    end

    defp child?(state, parent, id) when is_binary(id) do
      match?(%{"parent" => ^parent, "deleted" => false}, state["nodes"][id])
    end

    defp child?(_state, _parent, _id), do: false

    defp last_child(state, parent) do
      state["orders"]
      |> Map.get(parent, [])
      |> Enum.filter(&child?(state, parent, &1))
      |> List.last()
    end

    # In the document: the node and each of its parents not deleted, up to
    # the root.
    defp reachable?(state, id) do
      case state["nodes"][id] do
        %{"deleted" => true} -> false
        %{"parent" => nil} -> id == state["root"]
        %{"parent" => parent} -> reachable?(state, parent)
        nil -> false
      end
    end
  end
end
