defmodule KotobaTest.Post do
  @moduledoc """
  A test schema with a `Kotoba.Content` field, for changeset tests.

  There is no database in this repository: the schema is `embedded_schema`
  and the tests build and cast changesets in memory.
  """
  use Ecto.Schema

  import Ecto.Changeset

  embedded_schema do
    field :body, Kotoba.Content
  end

  @doc """
  Casts `attrs` into a changeset for `post`.

  `empty_values: []` turns off Ecto's default of treating an empty string
  as `nil`: an empty `body` is a meaningful value for `Kotoba.Content`
  (`Kotoba.Content.empty/0`), not an absent one.
  """
  @spec changeset(Ecto.Schema.t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(post, attrs), do: cast(post, attrs, [:body], empty_values: [])
end
