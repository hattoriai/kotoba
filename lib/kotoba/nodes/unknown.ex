defmodule Kotoba.Nodes.Unknown do
  @moduledoc """
  A node of a type that is not in the node registry.

  `Kotoba.Document.parse/2` keeps the JSON map of the node in `raw`, with
  its children, and `to_json/1` returns it with no change. Kotoba does not
  read the children of an unknown node.
  """

  @enforce_keys [:type, :raw]
  defstruct [:type, :raw]

  @type t :: %__MODULE__{type: String.t(), raw: map()}

  @doc "Builds an unknown node from its JSON map."
  @spec from_json(map()) :: t()
  def from_json(%{"type" => type} = json) when is_binary(type),
    do: %__MODULE__{type: type, raw: json}

  @doc "Returns the JSON map of the node."
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{raw: raw}), do: raw
end
