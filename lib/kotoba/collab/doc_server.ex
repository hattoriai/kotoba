defmodule Kotoba.Collab.DocServer do
  @moduledoc """
  The Phoenix authority for a shared document.

  Transactions are checked, persisted atomically, and then broadcast to
  subscribed channel processes. Process monitors track live participants.
  An idle process exits after its TTL; durable state stays in the store.
  """

  use GenServer, restart: :temporary

  alias Kotoba.Collab.Document

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  def subscribe(server, pid, participant, pending \\ []),
    do: GenServer.call(server, {:subscribe, pid, participant, pending})

  def commit(server, transaction, author),
    do: GenServer.call(server, {:commit, transaction, author}, 15_000)

  def snapshot(server), do: GenServer.call(server, :snapshot)

  def content_at(server, epoch, revision),
    do: GenServer.call(server, {:content_at, epoch, revision})

  def awareness(server, pid, selection), do: GenServer.cast(server, {:awareness, pid, selection})

  @impl GenServer
  def init(opts) do
    {store, context} = Keyword.fetch!(opts, :store)
    id = Keyword.fetch!(opts, :document_id)
    policy = Keyword.get(opts, :policy, [])

    with {:ok, loaded} <- store.load(context, id),
         {:ok, document} <- load_document(loaded, policy),
         {:ok, content} <- Document.validate(document, policy),
         :ok <- initialize(store, context, id, loaded.state, document, content) do
      ttl = Keyword.get(opts, :ttl, 30_000)

      {:ok,
       %{
         id: id,
         store: store,
         context: context,
         document: document,
         content: content,
         policy: policy,
         peers: %{},
         monitors: %{},
         ttl: ttl,
         timer: Process.send_after(self(), :expire, ttl),
         max_bytes: Keyword.get(opts, :max_bytes, 16_000_000)
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp load_document(%{state: nil, content: content}, policy), do: Document.new(content, policy)
  defp load_document(%{state: %{"v" => 1, "schema" => 1} = state}, _policy), do: {:ok, state}
  defp load_document(_loaded, _policy), do: {:error, :unsupported_version}

  defp initialize(store, context, id, nil, document, content),
    do: store.save(context, id, nil, document, content)

  defp initialize(_store, _context, _id, _loaded, _document, _content), do: :ok

  @impl GenServer
  def handle_call({:subscribe, pid, participant, pending}, _from, state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    state =
      if Map.has_key?(state.peers, pid),
        do: state,
        else: %{state | monitors: Map.put(state.monitors, Process.monitor(pid), pid)}

    state = %{
      state
      | peers: Map.put(state.peers, pid, Map.put(participant, "selection", nil)),
        timer: nil
    }

    broadcast(state, "presence", %{"people" => people(state)})

    accepted =
      Enum.filter(pending, fn id ->
        get_in(state.document, ["receipts", id, "author"]) == participant["user"]["id"]
      end)

    {:reply, {:ok, Map.put(payload(state), "accepted", accepted)}, state}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, {:ok, payload(state)}, state}

  def handle_call({:content_at, epoch, revision}, _from, state),
    do: {:reply, Document.at_revision(state.document, epoch, revision, state.policy), state}

  def handle_call({:commit, transaction, author}, _from, state) do
    case Document.commit(state.document, transaction, author, state.policy) do
      {:ok, document, content, event} ->
        persist(state, document, content, event)

      {:duplicate, revision} ->
        {:reply, {:ok, %{"id" => transaction["id"], "revision" => revision, "duplicate" => true}},
         state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp persist(state, document, content, event) do
    expected = {state.document["epoch"], state.document["revision"]}

    result =
      if byte_size(JSON.encode!(document)) <= state.max_bytes,
        do: state.store.save(state.context, state.id, expected, document, content),
        else: {:error, :document_too_large}

    case result do
      :ok ->
        state = %{state | document: document, content: content}
        broadcast(state, "transaction", event)
        {:reply, {:ok, event}, state}

      {:error, :conflict} ->
        {:stop, :normal, {:error, :stale_owner}, state}

      {:error, reason} ->
        {:reply, {:error, {:storage, reason}}, state}
    end
  end

  @impl GenServer
  def handle_cast({:awareness, pid, selection}, state) do
    if Map.has_key?(state.peers, pid) do
      state = put_in(state, [:peers, pid, "selection"], selection)
      broadcast(state, "presence", %{"people" => people(state)})
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {pid, monitors} = Map.pop(state.monitors, ref)
    state = %{state | monitors: monitors, peers: Map.delete(state.peers, pid)}
    broadcast(state, "presence", %{"people" => people(state)})

    timer =
      if map_size(state.peers) == 0,
        do: Process.send_after(self(), :expire, state.ttl),
        else: state.timer

    {:noreply, %{state | timer: timer}}
  end

  def handle_info(:expire, %{peers: peers} = state) when map_size(peers) == 0,
    do: {:stop, :normal, state}

  def handle_info(:expire, state), do: {:noreply, state}

  defp people(state), do: state.peers |> Map.values() |> Enum.sort_by(& &1["session"])

  defp payload(state),
    do: %{
      "state" => Document.snapshot(state.document),
      "content" => state.content.doc,
      "people" => people(state)
    }

  defp broadcast(state, event, payload),
    do: Enum.each(Map.keys(state.peers), &send(&1, {:kotoba_collab, event, payload}))
end
