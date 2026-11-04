defmodule Kotoba.Collab.UploadTest do
  use ExUnit.Case, async: false

  alias Kotoba.Collab.{Store, Upload}
  alias Kotoba.Nodes.Attachment

  # A person's upload in a shared editor goes in the shared document from
  # the server, at the place its marker had: these are the rules of that
  # place when the document changed meanwhile.

  defmodule Policy do
    @moduledoc false
    @behaviour Issho.Policy

    @impl true
    def authorize(_identity, _document_id, _action), do: :ok

    @impl true
    def document(_identity, _document_id),
      do: Kotoba.Issho.document(store: {Store.Memory, :kotoba_upload_store})
  end

  setup do
    start_supervised!({Store.Memory, name: :kotoba_upload_store})
    instance = Issho.Test.start!(policy: Policy)
    %{issho: [instance: instance, document: "post:#{System.unique_integer([:positive])}"]}
  end

  defp file(name),
    do: %Attachment{
      key: "2026/11/#{name}",
      url: "/uploads/2026/11/#{name}",
      name: name,
      content_type: "image/png",
      bytes: 10
    }

  defp state(issho) do
    {:ok, pid} = Issho.Documents.open(issho[:instance], issho[:document])
    {:ok, %{"state" => state}} = Issho.Authority.snapshot(pid)
    state
  end

  defp change(issho, ops),
    do: {:ok, _} = Kotoba.Issho.change(issho[:instance], issho[:document], ops)

  defp block(issho, id, type, parent \\ nil, after_id \\ nil) do
    parent = parent || state(issho)["root"]

    change(issho, [
      %{
        "op" => "insert_node",
        "id" => id,
        "parent" => parent,
        "after" => after_id,
        "data" => %{"type" => type, "version" => 1},
        "element" => true
      }
    ])
  end

  defp delete(issho, id),
    do: change(issho, [%{"op" => "node_visibility", "id" => id, "deleted" => true, "tag" => id}])

  # The live children of `parent`: the name of a file, else the id.
  defp children(issho, parent \\ nil) do
    state = state(issho)
    parent = parent || state["root"]

    state["orders"][parent]
    |> Enum.reject(&(state["nodes"][&1]["deleted"] or state["nodes"][&1]["parent"] != parent))
    |> Enum.map(&(state["nodes"][&1]["data"]["name"] || &1))
  end

  test "goes after the block that held its marker", %{issho: issho} do
    block(issho, "one", "paragraph")
    block(issho, "two", "paragraph", nil, "one")

    assert {:ok, _id} = Upload.insert(issho, file("a.png"), %{"parent" => nil, "after" => "one"})
    assert ["one", "a.png", "two"] = children(issho) -- ["seed:1"]
  end

  test "files handed in together keep their order in a gallery, whichever goes in first",
       %{issho: issho} do
    block(issho, "one", "paragraph")
    block(issho, "pictures", "gallery", nil, "one")

    place =
      &%{"parent" => "pictures", "after" => nil, "first" => true, "batch" => "b", "index" => &1}

    {:ok, c} = Upload.insert(issho, file("c.png"), place.(2), %{})
    {:ok, a} = Upload.insert(issho, file("a.png"), place.(0), %{2 => c})
    {:ok, _b} = Upload.insert(issho, file("b.png"), place.(1), %{0 => a, 2 => c})

    assert children(issho, "pictures") == ["a.png", "b.png", "c.png"]
  end

  test "a gallery deleted meanwhile: the file goes at the end of the document", %{issho: issho} do
    block(issho, "one", "paragraph")
    block(issho, "pictures", "gallery", nil, "one")
    block(issho, "two", "paragraph", nil, "pictures")
    delete(issho, "pictures")

    {:ok, _id} = Upload.insert(issho, file("a.png"), %{"parent" => "pictures", "first" => true})
    assert List.last(children(issho)) == "a.png"
  end

  test "a block deleted meanwhile, or one the server does not have: at the end", %{issho: issho} do
    block(issho, "one", "paragraph")
    block(issho, "two", "paragraph", nil, "one")
    delete(issho, "one")

    {:ok, _id} = Upload.insert(issho, file("a.png"), %{"parent" => nil, "after" => "one"})
    {:ok, _id} = Upload.insert(issho, file("b.png"), %{"parent" => nil, "after" => "unknown"})
    assert ["two", "a.png", "b.png"] = children(issho) -- ["seed:1"]
  end

  test "a document that refuses it gives the error", %{issho: issho} do
    assert {:error, _reason} =
             Upload.insert(issho, %{file("a.png") | url: "javascript:alert(1)"}, %{
               "parent" => nil
             })
  end
end
