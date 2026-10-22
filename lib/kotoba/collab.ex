if Code.ensure_loaded?(Issho) do
  defmodule Kotoba.Collab do
    @moduledoc """
    Collaboration for Kotoba on [Issho](https://hex.pm/packages/issho):
    Issho is the document's authority, its people and their cursors;
    Kotoba is the document and its editor.

    Your Issho policy names Kotoba's documents with `document/1`, the
    editor joins with its `issho` option (`Issho.Join`'s keys, as every
    component of the page, and Kotoba's `:undo`), and the application's
    JavaScript imports `kotoba/collab` once. Changes from your own code go
    through `Kotoba.Issho.change/4`. See the Collaboration guide.
    """

    @doc false
    @deprecated "Use Kotoba.Issho.document/1"
    def document(opts), do: Kotoba.Issho.document(opts)

    @doc false
    # The editor's credentials, from its `issho` option (`Issho.Join`, and
    # Kotoba's own `:undo`, `:socket` and `:max_channels`) and its `user`:
    # an Issho grant for the document's room, which the LiveView renews
    # when the editor asks, after asking the policy again
    # (`Issho.Live.grant/4`). Kept for the LiveView's life, so that a
    # render signs no new token.
    @spec credentials(keyword() | map() | Issho.Join.t(), term()) :: map()
    def credentials(issho, user) do
      join = Issho.Join.new!(issho, [:undo, :socket, :max_channels])

      if is_nil(user),
        do: raise(ArgumentError, "<.kotoba issho={...}> needs user, the person who edits")

      {actor, person} = person(user)
      key = {__MODULE__, :credentials, join, actor}

      case Process.get(key) do
        nil -> tap(sign(join, actor, person), &Process.put(key, &1))
        credentials -> credentials
      end
    end

    defp sign(%Issho.Join{} = join, actor, person) do
      max_channels = Map.get(join.extra, :max_channels, 100)

      unless is_integer(max_channels) and max_channels > 0,
        do: raise(ArgumentError, "issho's :max_channels must be a positive integer")

      grant =
        Issho.Live.grant(
          join.instance,
          actor,
          join.room,
          Issho.Join.grant_opts(join) ++
            [socket: Map.get(join.extra, :socket, "/issho/socket"), max_channels: max_channels]
        )

      %{
        "document_id" => join.document,
        "room" => join.room,
        "token" => grant["token"],
        "socket" => grant["socket"],
        "max_channels" => max_channels,
        "user" => person,
        "role" => Atom.to_string(join.can),
        "people" => join.people,
        "follow" => join.follow,
        "undo" => undo(Map.get(join.extra, :undo, :editor))
      }
    end

    # The person as the app's Issho.Actor says them (their key, name and
    # colour), the same in every room of the page: an editor, a canvas,
    # Issho's lists. A map with an `:id` and no implementation is the
    # actor `"7"`, as Issho takes it.
    defp person(user) do
      key = Issho.Actor.key(user)
      shown = Issho.Actor.display(user)
      name = to_string(shown[:name] || Map.get(user, :name) || "Anonymous")
      color = Issho.Color.sanitize(shown[:color] || Map.get(user, :color))

      actor =
        %{id: key, name: name, color: color, avatar: shown[:avatar], kind: shown[:kind]}
        |> Map.reject(fn {_field, value} -> is_nil(value) end)

      {actor,
       %{
         "id" => key,
         "name" => name,
         "color" => color || "var(--issho-person-#{Issho.Color.index(key)}, #2563eb)"
       }}
    end

    defp undo(mode) when mode in [:editor, :page], do: Atom.to_string(mode)
    defp undo(false), do: false

    defp undo(other),
      do:
        raise(
          ArgumentError,
          "issho's :undo is :editor, :page or false, got: #{inspect(other)}"
        )

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

    @doc false
    @deprecated "Use Kotoba.Issho.change/4"
    def transact(instance, document_id, operations_or_transaction, opts \\ []),
      do: Kotoba.Issho.change(instance, document_id, operations_or_transaction, opts)
  end
end
