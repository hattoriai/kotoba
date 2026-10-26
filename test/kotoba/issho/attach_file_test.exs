defmodule Kotoba.Issho.AttachFileTest do
  use ExUnit.Case, async: false

  import Sake.Test

  alias Issho.Participant
  alias Kotoba.Collab.{Document, Store}
  alias Kotoba.Content

  defmodule MCP do
    @moduledoc false
    use Issho.MCP, name: "kotoba-attach-test", version: "0.0.0", tools: Kotoba.Issho.tools()
  end

  defmodule Policy do
    @moduledoc false
    @behaviour Issho.Policy

    @impl true
    def authorize(_identity, _room, _action), do: :ok

    @impl true
    def document(_identity, _id),
      do: Kotoba.Issho.document(store: {Store.Memory, :kotoba_attach_store})
  end

  # Keeps what it is given, for the test that runs the tool.
  defmodule Storage do
    @moduledoc false
    @behaviour Kotoba.Storage

    @impl true
    def put(key, path, meta) do
      send(Application.fetch_env!(:kotoba, :attach_test_pid), {:put, key, File.read!(path), meta})
      {:ok, url(key)}
    end

    @impl true
    def url(key), do: "/files/" <> key

    @impl true
    def delete(key), do: send(Application.fetch_env!(:kotoba, :attach_test_pid), {:deleted, key})
  end

  @pdf "%PDF-1.7\n1 0 obj << /Type /Catalog >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n"

  setup do
    start_supervised!({Store.Memory, name: :kotoba_attach_store})
    instance = Issho.Test.start!(policy: Policy)
    Application.put_env(:issho, Issho.MCP, instance: instance)
    Application.put_env(:kotoba, :attach_test_pid, self())
    previous = Application.get_env(:kotoba, Kotoba.Issho)

    Application.put_env(:kotoba, Kotoba.Issho,
      pace: 0,
      travel: false,
      attach: [storage: Storage, max_bytes: 1_000]
    )

    on_exit(fn ->
      Application.delete_env(:issho, Issho.MCP)
      Application.delete_env(:kotoba, :attach_test_pid)

      if previous,
        do: Application.put_env(:kotoba, Kotoba.Issho, previous),
        else: Application.delete_env(:kotoba, Kotoba.Issho)
    end)

    document = "notebook:#{System.unique_integer([:positive])}/bills"

    :ok =
      Store.Memory.seed(
        :kotoba_attach_store,
        document,
        Content.from_markdown(
          "Electricity, November\n\n- Due on the 5th\n- 62.40 EUR\n\nPaid by transfer"
        )
      )

    {:ok, ada} = Issho.join_as(instance, %{id: "ada", name: "Ada"}, Issho.Policy.room(document))
    {:ok, _} = Participant.open(ada, document)

    %{document: document, ada: ada, client: connect(MCP)}
  end

  defp html(ada, document) do
    {:ok, %{"state" => state}} = Participant.read(ada, document)
    {:ok, content} = Document.validate(state)
    content.html
  end

  defp call(client, args) do
    case call_tool(client, "attach_file", args) do
      {:ok, %{is_error: true, text: text}} -> {:error, text}
      {:ok, %{structured: structured}} -> {:ok, structured}
    end
  end

  test "attaches a PDF after a block, and everyone sees it", %{
    client: client,
    document: document,
    ada: ada
  } do
    assert {:ok, %{"attached" => "edp-2026-11.pdf", "content_type" => "application/pdf"}} =
             call(client, %{
               "document" => document,
               "after" => 1,
               "name" => "edp-2026-11.pdf",
               "data" => Base.encode64(@pdf),
               "caption" => "The invoice"
             })

    assert_received {:put, key, @pdf, %{content_type: "application/pdf"}}
    assert key =~ "edp-2026-11.pdf"

    html = html(ada, document)

    assert html =~
             ~r{<p>Electricity, November</p><figure class="kotoba-attachment kotoba-attachment-pdf"}

    assert html =~ "The invoice"
    assert html =~ "/files/#{key}"
  end

  test "after a list, not inside it", %{client: client, document: document, ada: ada} do
    {:ok, _} =
      call(client, %{
        "document" => document,
        "after" => 2,
        "name" => "edp.pdf",
        "data" => Base.encode64(@pdf)
      })

    assert html(ada, document) =~
             ~r{</ul><figure class="kotoba-attachment kotoba-attachment-pdf".*</figure><p>Paid by transfer</p>}s
  end

  test "first, and from a data URL", %{client: client, document: document, ada: ada} do
    {:ok, _} =
      call(client, %{
        "document" => document,
        "after" => 0,
        "name" => "edp.pdf",
        "data" => "data:application/pdf;base64," <> Base.encode64(@pdf)
      })

    assert html(ada, document) =~ ~r{^<figure class="kotoba-attachment kotoba-attachment-pdf"}
  end

  test "a web page named as a PDF is a download", %{client: client, document: document, ada: ada} do
    page = "<html><script>alert(1)</script></html>"

    assert {:ok, %{"content_type" => "application/octet-stream"}} =
             call(client, %{
               "document" => document,
               "after" => 1,
               "name" => "invoice.pdf",
               "data" => Base.encode64(page),
               "content_type" => "application/pdf"
             })

    assert_received {:put, key, ^page, _meta}
    assert key =~ ~r/\.bin$/
    refute html(ada, document) =~ "kotoba-attachment-pdf"
  end

  test "refuses a file too large, data that is not base64, and a block that is not there", %{
    client: client,
    document: document
  } do
    big = :binary.copy("a", 1_001)

    assert {:error, "The file is larger than 1000 bytes."} =
             call(client, %{
               "document" => document,
               "after" => 1,
               "name" => "big.pdf",
               "data" => Base.encode64(big)
             })

    assert {:error, "`data` is not base64."} =
             call(client, %{
               "document" => document,
               "after" => 1,
               "name" => "x.pdf",
               "data" => "%%%"
             })

    assert {:error, message} =
             call(client, %{
               "document" => document,
               "after" => 9,
               "name" => "x.pdf",
               "data" => Base.encode64(@pdf)
             })

    assert message =~ "block 9"
    refute_received {:put, _key, _bytes, _meta}
  end
end
