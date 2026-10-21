defmodule Kotoba.Collab.Store do
  @moduledoc """
  Atomic persistence for collaboration state and its rendered content.

  `save/5` must compare the stored `{epoch, revision}` with `expected`
  and commit state and content together. `nil` means the document has no
  collaboration state yet. A stale owner must receive `{:error, :conflict}`.
  The document's authority (Issho's) acknowledges edits only after this
  callback succeeds.

  The state is a map of JSON values with `"epoch"` and `"revision"` keys:
  keep it as it is, in a map or JSON column. A state saved by Kotoba
  before Issho loads as it is too, and is saved in Issho's form with its
  next change.

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
