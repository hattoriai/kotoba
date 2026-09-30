defmodule Kotoba.Collab.Supervisor do
  @moduledoc """
  The application's supervisor for collaborative documents.

      {Kotoba.Collab.Supervisor,
       name: MyApp.CollabSupervisor, store: {MyApp.CollabStore, MyApp.Repo}}

  The default registry is `:global`, for single nodes and fully connected
  BEAM clusters. `:registry` can be a module exporting `name/2`, returning
  a GenServer name for the supervisor identity and document ID.
  """

  use DynamicSupervisor

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl DynamicSupervisor
  def init(opts), do: DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [opts])

  @doc false
  def open(supervisor, id, opts \\ []) do
    case DynamicSupervisor.start_child(
           supervisor,
           {Kotoba.Collab.Supervisor.Child, [document_id: id] ++ opts}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, {:shutdown, {:failed_to_start_child, _id, {:already_started, pid}}}} -> {:ok, pid}
      error -> error
    end
  end
end

defmodule Kotoba.Collab.Supervisor.Child do
  alias Kotoba.Collab.DocServer
  @moduledoc false

  def child_spec(opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}

  def start_link(config, opts) do
    supervisor = Keyword.fetch!(config, :name)
    id = Keyword.fetch!(opts, :document_id)

    name =
      case Keyword.get(config, :registry, :global) do
        :global -> {:global, {Kotoba.Collab.DocServer, supervisor, id}}
        module -> module.name(supervisor, id)
      end

    DocServer.start_link(Keyword.merge(config, opts) |> Keyword.put(:name, name))
  end
end
