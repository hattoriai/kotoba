defmodule Kotoba.Collab do
  @moduledoc """
  Collaboration for Kotoba with Phoenix as the document authority.

  Import `kotoba/collab` once in the application's JavaScript, mount
  `Kotoba.Collab.Channel` on an application socket, and pass `token/3` to
  the component's `collab` attribute. See the Collaboration guide.
  """

  alias Kotoba.Collab.{DocServer, Document, Supervisor}

  @salt "kotoba-collab-v1"

  @doc "Makes short-lived join credentials from the LiveView's authenticated user."
  def token(socket_or_endpoint, document_id, opts) when is_binary(document_id) do
    user = Keyword.fetch!(opts, :user)
    role = Keyword.get(opts, :role, :write)

    unless role in [:read, :write],
      do: raise(ArgumentError, "collaboration role must be :read or :write")

    user = %{
      "id" => to_string(Map.fetch!(user, :id)),
      "name" => to_string(Map.get(user, :name, "Anonymous")),
      "color" => Map.get(user, :color, "#2563eb")
    }

    signed =
      Phoenix.Token.sign(socket_or_endpoint, @salt, %{
        "document_id" => document_id,
        "role" => Atom.to_string(role),
        "user" => user
      })

    %{
      "document_id" => document_id,
      "token" => signed,
      "socket" => Keyword.get(opts, :socket, "/kotoba/socket"),
      "user" => user,
      "role" => Atom.to_string(role)
    }
  end

  @doc false
  def verify(endpoint, token), do: Phoenix.Token.verify(endpoint, @salt, token, max_age: 300)

  @doc "Reads the current durably accepted content and revision for a form commit."
  def content(supervisor, document_id) do
    with {:ok, server} <- Supervisor.open(supervisor, document_id), do: DocServer.snapshot(server)
  end

  @doc "Reads the exact accepted revision posted by a collaboration form."
  def content(supervisor, document_id, %{"epoch" => epoch, "revision" => revision}) do
    with {:ok, server} <- Supervisor.open(supervisor, document_id),
         do: DocServer.content_at(server, epoch, revision)
  end

  @doc "Applies backend operations through the same validation and persistence path."
  def transact(supervisor, document_id, operations_or_transaction, opts \\ [])

  def transact(supervisor, document_id, %{"ops" => _} = transaction, opts) do
    with {:ok, server} <- Supervisor.open(supervisor, document_id),
         do: DocServer.commit(server, transaction, Keyword.get(opts, :author, "server"))
  end

  def transact(supervisor, document_id, operations, opts) when is_list(operations) do
    with {:ok, server} <- Supervisor.open(supervisor, document_id),
         {:ok, %{"state" => state}} <- DocServer.snapshot(server) do
      transaction = %{
        "v" => 1,
        "schema" => state["schema"],
        "epoch" => state["epoch"],
        "id" => Keyword.get(opts, :id, Document.random_id()),
        "base_revision" => state["revision"],
        "ops" => operations
      }

      DocServer.commit(server, transaction, Keyword.get(opts, :author, "server"))
    end
  end
end
