defmodule Kotoba.Collab.FailingStore do
  @behaviour Kotoba.Collab.Store
  alias Kotoba.Collab.Store.Memory
  def load({store, _flag}, id), do: Memory.load(store, id)

  def save({store, flag}, id, expected, document, content) do
    if Agent.get(flag, & &1),
      do: {:error, :unavailable},
      else: Memory.save(store, id, expected, document, content)
  end
end

defmodule Kotoba.Collab.DocServerTest do
  use ExUnit.Case, async: true

  alias Kotoba.Collab.{DocServer, Document, Store, Supervisor}

  setup do
    store = start_supervised!(Store.Memory)
    name = Module.concat(__MODULE__, "Supervisor#{System.unique_integer([:positive])}")
    start_supervised!({Supervisor, name: name, store: {Store.Memory, store}, ttl: 1_000})
    %{supervisor: name, store: store}
  end

  test "server-owned bootstrap is race safe and persists before its first join", %{
    supervisor: supervisor,
    store: store
  } do
    results =
      1..10
      |> Task.async_stream(fn _ -> Supervisor.open(supervisor, "shared") end)
      |> Enum.map(fn {:ok, {:ok, pid}} -> pid end)

    assert results |> Enum.uniq() |> length() == 1

    assert {:ok, %{state: %{"revision" => 0}, content: %Kotoba.Content{}}} =
             Store.Memory.load(store, "shared")
  end

  test "accepted transactions survive an authority restart", %{
    supervisor: supervisor,
    store: store
  } do
    :ok = Store.Memory.seed(store, "shared", Kotoba.Content.from_markdown("abc"))
    {:ok, pid} = Supervisor.open(supervisor, "shared")
    {:ok, %{"state" => state}} = DocServer.snapshot(pid)

    tx = %{
      "v" => 1,
      "schema" => 1,
      "epoch" => state["epoch"],
      "id" => Document.random_id(),
      "base_revision" => 0,
      "ops" => [
        %{
          "op" => "set_text_attrs",
          "id" => "seed:2",
          "atoms" => ["seed:2:0"],
          "values" => %{"bold" => true}
        }
      ]
    }

    assert {:ok, %{"revision" => 1}} = DocServer.commit(pid, tx, "alice")

    assert {:ok, %{state: %{"revision" => 1}, content: %{html: "<p><strong>a</strong>bc</p>"}}} =
             Store.Memory.load(store, "shared")

    GenServer.stop(pid)
    {:ok, recovered} = Supervisor.open(supervisor, "shared")

    assert {:ok, %{"state" => %{"revision" => 1, "epoch" => epoch}}} =
             DocServer.snapshot(recovered)

    assert epoch == state["epoch"]
    assert {:ok, %{"duplicate" => true}} = DocServer.commit(recovered, tx, "alice")
  end

  test "compare-and-swap refuses stale owners", %{store: store} do
    {:ok, first} = Document.new()
    {:ok, content} = Document.validate(first)
    assert :ok = Store.Memory.save(store, "shared", nil, first, content)
    assert {:error, :conflict} = Store.Memory.save(store, "shared", nil, first, content)

    assert {:error, :conflict} =
             Store.Memory.save(store, "shared", {first["epoch"], 100}, first, content)
  end

  test "storage failures neither acknowledge nor broadcast an accepted transaction", %{
    store: store
  } do
    :ok = Store.Memory.seed(store, "failure", Kotoba.Content.from_markdown("abc"))
    flag = start_supervised!({Agent, fn -> false end})
    name = Module.concat(__MODULE__, "Failing#{System.unique_integer([:positive])}")

    start_supervised!(
      {Supervisor, name: name, store: {Kotoba.Collab.FailingStore, {store, flag}}},
      id: :failing_supervisor
    )

    {:ok, server} = Supervisor.open(name, "failure")
    participant = %{"session" => "session", "role" => "write", "user" => %{"id" => "alice"}}
    {:ok, %{"state" => state}} = DocServer.subscribe(server, self(), participant)
    assert_receive {:kotoba_collab, "presence", _}

    tx = %{
      "v" => 1,
      "schema" => 1,
      "epoch" => state["epoch"],
      "id" => Document.random_id(),
      "base_revision" => 0,
      "ops" => [
        %{
          "op" => "set_text_attrs",
          "id" => "seed:2",
          "atoms" => ["seed:2:0"],
          "values" => %{"bold" => true}
        }
      ]
    }

    Agent.update(flag, fn _ -> true end)
    assert {:error, {:storage, :unavailable}} = DocServer.commit(server, tx, "alice")
    refute_receive {:kotoba_collab, "transaction", _}
    assert {:ok, %{"state" => %{"revision" => 0}}} = DocServer.snapshot(server)

    assert {:ok, %{state: %{"revision" => 0}, content: %{text: "abc"}}} =
             Store.Memory.load(store, "failure")

    Agent.update(flag, fn _ -> false end)
    assert {:ok, %{"revision" => 1}} = DocServer.commit(server, tx, "alice")
    assert_receive {:kotoba_collab, "transaction", %{"revision" => 1}}
  end
end
