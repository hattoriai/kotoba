defmodule Kotoba.Collab.Store do
  @moduledoc """
  Atomic persistence for collaboration state and its rendered content.

  `save/5` must compare the stored `{epoch, revision}` with `expected`
  and commit state and content together. `nil` means the document has no
  collaboration state yet. A stale owner must receive `{:error, :conflict}`.
  A document process acknowledges edits only after this callback succeeds.

  The context is supplied by the application, for example a repository
  module or an options map. The guide includes an Ecto implementation.
  """

  @callback load(context :: term(), document_id :: String.t()) ::
              {:ok, %{state: map() | nil, content: Kotoba.Content.t() | nil}} | {:error, term()}
  @callback save(
              context :: term(),
              document_id :: String.t(),
              expected :: {String.t(), non_neg_integer()} | nil,
              state :: map(),
              content :: Kotoba.Content.t()
            ) :: :ok | {:error, term()}
end
