if Code.ensure_loaded?(Issho) do
  defmodule Kotoba.Collab do
    @moduledoc """
    Collaboration for Kotoba on [Issho](https://hex.pm/packages/issho):
    Issho is the document's authority, its people and their cursors;
    Kotoba is the document and its editor.

    Your Issho policy names Kotoba's documents with `document/1`, your
    LiveView signs `token/3` for the component's `collab` attribute, and
    the application's JavaScript imports `kotoba/collab` once. See the
    Collaboration guide.
    """

    alias Kotoba.Collab.Document

    @doc """
    What a shared editor's document is, for your policy's `document/2`.

        def document(_identity, _document_id),
          do: Kotoba.Collab.document(store: {MyApp.CollabStore, MyApp.Repo})

    Options: `:store` (required), your `Kotoba.Collab.Store` and its
    context; `:policy`, the document's checks (`:features`, `:nodes`,
    `:validate`), as every accepted transaction must pass them.
    """
    @spec document(keyword()) :: {:ok, map()}
    def document(opts) do
      {:ok,
       %{
         engine: Kotoba.Issho,
         opts: Keyword.get(opts, :policy, []),
         store: {Kotoba.Issho.Store, Keyword.fetch!(opts, :store)}
       }}
    end

    @doc """
    Makes short-lived join credentials from the LiveView's authenticated
    user, in a LiveView with Issho's hook (`on_mount Issho.Live`): an Issho
    grant for the document's room, which the LiveView renews when the
    editor asks, after asking the policy again (`Issho.Live.grant/4`).

    The credentials join the document's room (`Issho.Policy.room/1`): the
    part of its id before the first `"/"`, or the whole id. The editors of
    a page whose documents share a room (`"notebook:7/cell-1"`,
    `"notebook:7/cell-2"`) share its people, and a person's cursor goes
    from one editor to the other.

    Options: `:user` (required), `:role` (`:write` or `:read`), `:people`
    (whether the editor lists the room's people, `true`; `false` when the
    page shows Issho's list, `Issho.Components.people/1`), `:socket`
    (the Issho socket's path, `"/issho/socket"` by default) and
    `:max_channels` (that socket's `:max_channels_per_transport`, 100 by
    default).
    """
    @spec token(atom(), String.t(), keyword()) :: map()
    def token(instance, document_id, opts) when is_atom(instance) and is_binary(document_id) do
      user = Keyword.fetch!(opts, :user)
      role = Keyword.get(opts, :role, :write)

      unless role in [:read, :write],
        do: raise(ArgumentError, "collaboration role must be :read or :write")

      max_channels = Keyword.get(opts, :max_channels, 100)

      unless is_integer(max_channels) and max_channels > 0,
        do: raise(ArgumentError, "collaboration :max_channels must be a positive integer")

      user = %{
        "id" => to_string(Map.fetch!(user, :id)),
        "name" => to_string(Map.get(user, :name, "Anonymous")),
        "color" => Map.get(user, :color, "#2563eb")
      }

      actor = %{id: user["id"], name: user["name"], color: user["color"]}
      room = Issho.Policy.room(document_id)

      grant =
        Issho.Live.grant(instance, actor, room,
          can: role,
          socket: Keyword.get(opts, :socket, "/issho/socket"),
          max_channels: max_channels
        )

      %{
        "document_id" => document_id,
        "room" => room,
        "token" => grant["token"],
        "socket" => grant["socket"],
        "max_channels" => max_channels,
        "user" => user,
        "role" => Atom.to_string(role),
        "people" => Keyword.get(opts, :people, true)
      }
    end

    @doc """
    The document's accepted content now: `{:ok, %{"epoch" => ..., "revision"
    => ..., "content" => %Kotoba.Content{}}}`.
    """
    def content(instance, document_id) do
      with {:ok, pid} <- Issho.Documents.open(instance, document_id),
           do: Issho.Authority.content(pid)
    end

    @doc "The content of the exact accepted revision a collaboration form posted."
    def content(instance, document_id, %{"epoch" => epoch, "revision" => revision}),
      do: Issho.content(instance, document_id, epoch, revision)

    @doc """
    Applies backend operations through the same authority, checks and
    store as the editors' changes. Pass the original transaction map
    (with its `"id"` and `"base_revision"`) to retry one idempotently.
    Options: `:author` (`"server"`), `:id`.
    """
    def transact(instance, document_id, operations_or_transaction, opts \\ [])

    def transact(instance, document_id, %{"ops" => _} = transaction, opts) do
      with {:ok, pid} <- Issho.Documents.open(instance, document_id),
           do: Issho.Authority.commit(pid, transaction, Keyword.get(opts, :author, "server"))
    end

    def transact(instance, document_id, operations, opts) when is_list(operations) do
      opts = Keyword.put_new_lazy(opts, :id, &Document.random_id/0)
      Issho.transact(instance, document_id, operations, opts)
    end
  end
end
