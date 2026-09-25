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
  Casts `attrs` into a changeset for `post`, with Ecto's defaults.

  Like any other `Ecto.Type` field, a `""` or all-white-space `body` param
  is dropped before it reaches `Kotoba.Content.cast/1` (Ecto's default
  `empty_values`), so it gives no change, not `Kotoba.Content.empty/0`.
  See `changeset_with_empty_values/2` to opt out of that default.
  """
  @spec changeset(Ecto.Schema.t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(post, attrs), do: cast(post, attrs, [:body])

  @doc """
  Casts `attrs` into a changeset for `post`, with `empty_values: []`.

  A `""` `body` param reaches `Kotoba.Content.cast/1` and casts to
  `Kotoba.Content.empty/0`, instead of being dropped as in `changeset/2`.
  A host opts in this way when it wants that; `empty_values: []` applies
  to every field named in the same `cast/4` call, so a form with other
  string fields that should keep the default gives `:body` its own call,
  as here.
  """
  @spec changeset_with_empty_values(Ecto.Schema.t() | Ecto.Changeset.t(), map()) ::
          Ecto.Changeset.t()
  def changeset_with_empty_values(post, attrs), do: cast(post, attrs, [:body], empty_values: [])
end
