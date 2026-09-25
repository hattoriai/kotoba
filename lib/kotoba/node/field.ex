defmodule Kotoba.Node.Field do
  @moduledoc """
  The description of one attribute of a `Kotoba.Node`.

  `Kotoba.Node.field/3` makes one `Kotoba.Node.Field` for each attribute.
  `c:Kotoba.Node.fields/0` returns them in the order of declaration.

  ## Struct keys

    * `:name` - the struct key of the node, an atom.
    * `:key` - the JSON key.
    * `:type` - `:string`, `:integer`, `:boolean`, `:map` or `{:array, type}`.
    * `:required`, `:default`, `:in` and `:omit_nil` - the values of the
      options below.

  ## Options of `field/3`

    * `:key` - the JSON key. The default is the name as a string.
    * `:required` - when `true`, the value must not be `nil`. The default is
      `false`.
    * `:default` - the struct default. `from_json/1` also uses it when the
      JSON has no value for the key. The default is `nil`.
    * `:in` - when set, a list of the permitted values.
    * `:omit_nil` - when `true`, `to_json/1` does not write the key if the
      value is `nil`. When `false` (the default), `to_json/1` writes `null`.
  """

  @enforce_keys [:name, :key, :type]
  defstruct [:name, :key, :type, :default, :in, required: false, omit_nil: false]

  @typedoc "A field type."
  @type type :: :string | :integer | :boolean | :map | {:array, type()}

  @type t :: %__MODULE__{
          name: atom(),
          key: String.t(),
          type: type(),
          required: boolean(),
          default: term(),
          in: [term()] | nil,
          omit_nil: boolean()
        }

  @options [:key, :required, :default, :in, :omit_nil]

  @doc """
  Builds a field. Raises `ArgumentError` when the name, the type or an
  option is not valid.
  """
  @spec new(atom(), type(), keyword()) :: t()
  def new(name, type, opts \\ []) when is_atom(name) and is_list(opts) do
    unless valid_type?(type) do
      raise ArgumentError, "invalid type #{inspect(type)} for field #{inspect(name)}"
    end

    case Keyword.keys(opts) -- @options do
      [] ->
        :ok

      unknown ->
        raise ArgumentError, "unknown options #{inspect(unknown)} for field #{inspect(name)}"
    end

    %__MODULE__{
      name: name,
      key: Keyword.get(opts, :key, Atom.to_string(name)),
      type: type,
      required: Keyword.get(opts, :required, false),
      default: Keyword.get(opts, :default),
      in: Keyword.get(opts, :in),
      omit_nil: Keyword.get(opts, :omit_nil, false)
    }
  end

  @doc """
  Checks one value against the field. Returns `:ok` or `{:error, message}`.
  """
  @spec check(t(), term()) :: :ok | {:error, String.t()}
  def check(%__MODULE__{required: true, key: key}, nil), do: {:error, "#{key} is required"}
  def check(%__MODULE__{}, nil), do: :ok

  def check(%__MODULE__{} = field, value) do
    cond do
      not type?(field.type, value) ->
        {:error, "#{field.key} must be #{describe(field.type)}"}

      field.in != nil and value not in field.in ->
        {:error, "#{field.key} must be one of: #{permitted(field.in)}"}

      true ->
        :ok
    end
  end

  defp valid_type?(type) when type in [:string, :integer, :boolean, :map], do: true
  defp valid_type?({:array, type}), do: valid_type?(type)
  defp valid_type?(_type), do: false

  defp type?(:string, value), do: is_binary(value)
  defp type?(:integer, value), do: is_integer(value)
  defp type?(:boolean, value), do: is_boolean(value)
  defp type?(:map, value), do: is_map(value)
  defp type?({:array, type}, value), do: is_list(value) and Enum.all?(value, &type?(type, &1))

  defp describe(:string), do: "a string"
  defp describe(:integer), do: "an integer"
  defp describe(:boolean), do: "a boolean"
  defp describe(:map), do: "an object"
  defp describe({:array, type}), do: "a list of #{plural(type)}"

  defp plural(:string), do: "strings"
  defp plural(:integer), do: "integers"
  defp plural(:boolean), do: "booleans"
  defp plural(:map), do: "objects"
  defp plural({:array, type}), do: "lists of #{plural(type)}"

  defp permitted(values), do: Enum.map_join(values, ", ", &to_string/1)
end
