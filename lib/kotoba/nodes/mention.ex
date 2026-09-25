defmodule Kotoba.Nodes.Mention do
  @moduledoc """
  A mention of a thing in the app (type `"mention"`), for example a person.

    * `kind` - the prompt kind that made the mention, for example `"people"`.
    * `id` - the ID of the thing, as a string.
    * `label` - the text that the reader sees.
  """
  use Kotoba.Node, type: "mention", kind: :decorator

  field :kind, :string, required: true
  field :id, :string, required: true
  field :label, :string, required: true
end
