defmodule Kotoba.Collab.Store.Memory do
  @moduledoc """
  An in-memory collaboration store for development and tests.

  Start it under your supervisor and pass its name or PID as the store
  context. It survives document-process restarts, but not a node restart.
  Production applications should supply a durable `Kotoba.Collab.Store`.
  """

  use GenServer
  @behaviour Kotoba.Collab.Store

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, %{}, opts)
  @impl GenServer
  def init(state), do: {:ok, state}

  @impl Kotoba.Collab.Store
  def load(server, id), do: GenServer.call(server, {:load, id})
  @impl Kotoba.Collab.Store
  def save(server, id, expected, state, content),
    do: GenServer.call(server, {:save, id, expected, state, content})

  @doc "Seeds a document before its first collaboration join."
  def seed(server, id, content), do: GenServer.call(server, {:seed, id, content})

  @impl GenServer
  def handle_call({:load, id}, _from, state),
    do: {:reply, {:ok, Map.get(state, id, %{state: nil, content: nil})}, state}

  def handle_call({:seed, id, content}, _from, state) do
    if Map.has_key?(state, id),
      do: {:reply, {:error, :exists}, state},
      else: {:reply, :ok, Map.put(state, id, %{state: nil, content: content})}
  end

  def handle_call({:save, id, expected, document, content}, _from, state) do
    stored = get_in(state, [id, :state])
    revision = if stored, do: {stored["epoch"], stored["revision"]}

    if revision == expected,
      do: {:reply, :ok, Map.put(state, id, %{state: document, content: content})},
      else: {:reply, {:error, :conflict}, state}
  end
end
