defmodule Kotoba.Node do
  @moduledoc """
  The behaviour of a node in a `Kotoba.Document`.

  A node is a struct that mirrors one Lexical node in the serialized editor
  state. `use Kotoba.Node` makes the struct and the functions of the
  behaviour from a list of fields:

      defmodule MyApp.Nodes.Pointer do
        use Kotoba.Node, type: "pointer", kind: :inline

        field :ref, :string, required: true
        field :excerpt, :string
      end

  ## Options

    * `:type` - the Lexical node type, as in the `"type"` key of the JSON.
      Required.
    * `:kind` - `:block`, `:inline` or `:decorator`. Required.
    * `:element` - when `true`, the node is a Lexical element node. It gets
      a `children` list and the element fields `direction`, `format` and
      `indent`. The default is `false`.

  Every node gets a `version` field (default `1`) and an `extra` map. The
  `extra` map keeps the JSON keys that the node does not declare, so
  `to_json/1` writes them back with no change.

  ## Fields

  `field/3` declares one attribute. See `Kotoba.Node.Field` for the options.
  The types are `:string`, `:integer`, `:boolean`, `:map` and
  `{:array, type}`. The names `:children`, `:extra`, `:type` and `:version`
  are reserved.

  ## Generated functions

  `use Kotoba.Node` defines `type/0`, `kind/0`, `element?/0`, `fields/0`,
  `validate/1`, `from_json/1` and `to_json/1`. A node can override
  `validate/1` to add its own checks, and call `super/1` for the field
  checks.

  `from_json/1` reads the attributes of one node. It does not read the
  children: `Kotoba.Document.parse/2` reads them with the node registry.

  ## Rendering

  The behaviour also declares `c:render_html/2`, `c:render_text/2` and
  `c:render_markdown/2`. They are optional callbacks of the behaviour, but
  the renderer requires `c:render_html/2` and `c:render_text/2` for each
  node that it outputs.
  """

  alias Kotoba.Node.Field

  @typedoc "The kind of a node."
  @type kind :: :block | :inline | :decorator

  @typedoc "A node struct."
  @type t :: struct()

  @doc "Returns the Lexical node type."
  @callback type() :: String.t()

  @doc "Returns the kind of the node."
  @callback kind() :: kind()

  @doc "Returns `true` when the node is a Lexical element node with children."
  @callback element?() :: boolean()

  @doc "Returns the fields of the node, in the order of declaration."
  @callback fields() :: [Field.t()]

  @doc "Checks the node. Returns `:ok` or `{:error, messages}`."
  @callback validate(node :: t()) :: :ok | {:error, [String.t()]}

  @doc "Builds the node from its JSON map. The children are not read."
  @callback from_json(json :: map()) :: t()

  @doc "Returns the JSON map of the node, with the JSON of its children."
  @callback to_json(node :: t()) :: map()

  @doc "Renders the node as safe HTML."
  @callback render_html(node :: t(), opts :: keyword()) :: Phoenix.HTML.safe()

  @doc "Renders the node as plain text."
  @callback render_text(node :: t(), opts :: keyword()) :: String.t()

  @doc "Renders the node as Markdown."
  @callback render_markdown(node :: t(), opts :: keyword()) :: String.t()

  @optional_callbacks render_html: 2, render_text: 2, render_markdown: 2

  @kinds [:block, :inline, :decorator]

  @doc false
  defmacro __using__(opts) do
    type = Keyword.fetch!(opts, :type)
    kind = Keyword.fetch!(opts, :kind)
    element = Keyword.get(opts, :element, false)

    quote do
      @behaviour Kotoba.Node
      import Kotoba.Node, only: [field: 2, field: 3]

      Module.register_attribute(__MODULE__, :kotoba_fields, accumulate: true)
      @kotoba_node Kotoba.Node.__options__(unquote(type), unquote(kind), unquote(element))
      @before_compile Kotoba.Node

      @impl Kotoba.Node
      def validate(node) when is_struct(node, __MODULE__), do: Kotoba.Node.validate_fields(node)

      defoverridable validate: 1
    end
  end

  @doc """
  Declares a field of the node. See `Kotoba.Node.Field` for the options.
  """
  defmacro field(name, type, opts \\ []) do
    quote do
      @kotoba_fields Kotoba.Node.__field__(unquote(name), unquote(type), unquote(opts))
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    %{element: element} = Module.get_attribute(env.module, :kotoba_node)
    declared = env.module |> Module.get_attribute(:kotoba_fields) |> Enum.reverse()
    fields = __fields__(declared, element)

    struct =
      Enum.map(fields, &{&1.name, &1.default}) ++
        [extra: %{}] ++ if(element, do: [children: []], else: [])

    quote do
      defstruct unquote(Macro.escape(struct))

      @type t :: %__MODULE__{}

      @impl Kotoba.Node
      def type, do: @kotoba_node.type

      @impl Kotoba.Node
      def kind, do: @kotoba_node.kind

      @impl Kotoba.Node
      def element?, do: @kotoba_node.element

      @impl Kotoba.Node
      def fields, do: unquote(Macro.escape(fields))

      @impl Kotoba.Node
      def from_json(json) when is_map(json), do: Kotoba.Node.from_json(__MODULE__, json)

      @impl Kotoba.Node
      def to_json(%__MODULE__{} = node), do: Kotoba.Node.to_json(node)
    end
  end

  @doc false
  def __options__(type, kind, element) do
    unless is_binary(type) and type != "",
      do: raise(ArgumentError, "the :type option must be a non-empty string")

    unless kind in @kinds,
      do: raise(ArgumentError, "the :kind option must be one of #{inspect(@kinds)}")

    unless is_boolean(element), do: raise(ArgumentError, "the :element option must be a boolean")
    %{type: type, kind: kind, element: element}
  end

  @reserved [:children, :extra, :type, :version]

  @doc false
  def __field__(name, type, opts) do
    if name in @reserved, do: raise(ArgumentError, "the field name #{inspect(name)} is reserved")
    Field.new(name, type, opts)
  end

  @doc false
  def __fields__(declared, element) do
    element_fields =
      if element do
        [
          Field.new(:direction, :string, in: ["ltr", "rtl"]),
          Field.new(:format, :string,
            default: "",
            in: ["", "left", "start", "center", "right", "end", "justify"]
          ),
          Field.new(:indent, :integer, default: 0)
        ]
      else
        []
      end

    fields =
      declared ++ element_fields ++ [Field.new(:version, :integer, default: 1, required: true)]

    case fields
         |> Enum.frequencies_by(& &1.name)
         |> Enum.filter(fn {_name, count} -> count > 1 end) do
      [] ->
        fields

      [{name, _count} | _rest] ->
        raise ArgumentError, "the field #{inspect(name)} is declared more than once"
    end
  end

  @doc """
  Checks every field of a node struct against its declaration.

  The generated `validate/1` calls this function.
  """
  @spec validate_fields(t()) :: :ok | {:error, [String.t()]}
  def validate_fields(%module{} = node) do
    errors =
      for field <- module.fields(),
          {:error, message} <- [Field.check(field, Map.fetch!(node, field.name))],
          do: message

    if errors == [], do: :ok, else: {:error, errors}
  end

  @doc """
  Builds a node struct of `module` from a JSON map.

  The generated `from_json/1` calls this function. A declared key that is
  not in the map gets the field default. The keys that the node does not
  declare go into `extra`. For an element node, the `"children"` key is not
  read and the struct gets no children.
  """
  @spec from_json(module(), map()) :: t()
  def from_json(module, json) when is_map(json) do
    rest = Map.delete(json, "type")
    rest = if module.element?(), do: Map.delete(rest, "children"), else: rest

    {attrs, extra} =
      Enum.reduce(module.fields(), {[], rest}, fn field, {attrs, rest} ->
        case Map.fetch(rest, field.key) do
          # A `null` that `to_json/1` would not write stays in `extra`.
          {:ok, nil} when field.omit_nil -> {[{field.name, nil} | attrs], rest}
          {:ok, value} -> {[{field.name, value} | attrs], Map.delete(rest, field.key)}
          :error -> {[{field.name, field.default} | attrs], rest}
        end
      end)

    struct(module, [{:extra, extra} | attrs])
  end

  @doc """
  Returns the JSON map of a node struct, with the JSON of its children.

  The generated `to_json/1` calls this function.
  """
  @spec to_json(t()) :: map()
  def to_json(%module{} = node) do
    json =
      Enum.reduce(module.fields(), node.extra, fn field, json ->
        case Map.fetch!(node, field.name) do
          nil when field.omit_nil -> json
          value -> Map.put(json, field.key, value)
        end
      end)

    json = Map.put(json, "type", module.type())

    if module.element?() do
      Map.put(json, "children", Enum.map(node.children, &encode/1))
    else
      json
    end
  end

  @doc """
  Returns the JSON map of any node, `Kotoba.Nodes.Unknown` included.
  """
  @spec encode(t()) :: map()
  def encode(%module{} = node), do: module.to_json(node)

  @doc """
  Returns `true` when `module` is a module that uses `Kotoba.Node`.
  """
  @spec node_module?(module()) :: boolean()
  def node_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :fields, 0) and
      function_exported?(module, :type, 0) and function_exported?(module, :element?, 0)
  end

  def node_module?(_other), do: false
end
