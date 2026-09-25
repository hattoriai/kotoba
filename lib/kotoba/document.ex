defmodule Kotoba.Document do
  @moduledoc """
  A rich text document in memory.

  The stored form of a document is an envelope around the serialized
  editor state of Lexical:

      %{"kotoba" => 1, "lexical" => "0.51", "root" => root_node_json}

  `parse/2` reads the envelope into a tree of node structs (see
  `Kotoba.Node`) and checks each node. `to_json/1` writes the envelope
  again. For the nodes in the registry, `to_json/1` writes the same JSON
  that `parse/2` read, when that JSON has all the keys that Lexical writes.
  A node of a type that is not in the registry becomes a
  `Kotoba.Nodes.Unknown` node, and `to_json/1` writes its JSON with no
  change.
  """

  alias Kotoba.Nodes
  alias Kotoba.Nodes.{Attachment, CodeHighlight, LineBreak, Mention, Root, Text, Unknown}

  @version 1

  @enforce_keys [:root]
  defstruct root: nil, version: @version, lexical: "0.51"

  @type t :: %__MODULE__{root: Root.t(), version: pos_integer(), lexical: String.t()}

  @envelope_keys ["kotoba", "lexical", "root"]

  @doc """
  Reads a document from its envelope, as a map or as a JSON string.

  Returns `{:ok, document}`, or `{:error, messages}` with one message for
  each problem.

  ## Options

    * `:nodes` - a list of extra `Kotoba.Node` modules for the registry. See
      `Kotoba.Nodes.registry/1`.

  ## Examples

      iex> {:ok, doc} =
      ...>   Kotoba.Document.parse(%{
      ...>     "kotoba" => 1,
      ...>     "lexical" => "0.51",
      ...>     "root" => %{"type" => "root", "children" => []}
      ...>   })
      iex> Kotoba.Document.empty?(doc)
      true

  """
  @spec parse(map() | String.t(), keyword()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(envelope, opts \\ [])

  def parse(json, opts) when is_binary(json) do
    case JSON.decode(json) do
      {:ok, envelope} -> parse(envelope, opts)
      {:error, _reason} -> {:error, ["the document is not valid JSON"]}
    end
  end

  def parse(envelope, opts) when is_map(envelope) do
    registry = Nodes.registry(Keyword.get(opts, :nodes, []))

    with :ok <- check_envelope(envelope),
         {:ok, root} <- parse_root(envelope["root"], registry) do
      {:ok, %__MODULE__{root: root, version: @version, lexical: envelope["lexical"]}}
    end
  end

  def parse(_other, _opts), do: {:error, ["the document must be a JSON object"]}

  defp check_envelope(envelope) do
    errors =
      Enum.map(
        Map.keys(envelope) -- @envelope_keys,
        &"unknown key #{inspect(&1)} in the document"
      ) ++
        envelope_errors(envelope)

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp envelope_errors(envelope) do
    [
      envelope["kotoba"] != @version && "kotoba must be #{@version}",
      not is_binary(envelope["lexical"]) && "lexical must be a string",
      not is_map(envelope["root"]) && "root must be an object"
    ]
    |> Enum.filter(& &1)
  end

  defp parse_root(%{"type" => "root"} = json, registry) do
    case parse_node(json, registry, "root", true) do
      {:ok, root} -> {:ok, root}
      {:error, errors} -> {:error, Enum.reverse(errors)}
    end
  end

  defp parse_root(_json, _registry), do: {:error, ["root must be a node of type \"root\""]}

  # Errors are collected in reverse order and reversed once in parse_root/2.
  defp parse_node(json, registry, path, top?) when is_map(json) do
    case json do
      %{"type" => "root"} when not top? ->
        {:error, ["#{path}: a root node can only be the top node"]}

      %{"type" => type} when is_binary(type) ->
        case registry do
          %{^type => module} -> parse_known(module, json, registry, path)
          %{} -> {:ok, Unknown.from_json(json)}
        end

      %{} ->
        {:error, ["#{path}: type must be a string"]}
    end
  end

  defp parse_node(_json, _registry, path, _top?),
    do: {:error, ["#{path}: a node must be an object"]}

  defp parse_known(module, json, registry, path) do
    node = module.from_json(json)
    label = "#{path} (#{module.type()})"

    own_errors =
      case module.validate(node) do
        :ok -> []
        {:error, messages} -> messages |> Enum.map(&"#{label}: #{&1}") |> Enum.reverse()
      end

    case parse_children(module, json, registry, path) do
      {:ok, children} when own_errors == [] -> {:ok, with_children(node, module, children)}
      {:ok, _children} -> {:error, own_errors}
      {:error, child_errors} -> {:error, child_errors ++ own_errors}
    end
  end

  defp with_children(node, module, children) do
    if module.element?(), do: %{node | children: children}, else: node
  end

  defp parse_children(module, json, registry, path) do
    cond do
      not module.element?() -> {:ok, []}
      not Map.has_key?(json, "children") -> {:ok, []}
      is_list(json["children"]) -> parse_list(json["children"], registry, path)
      true -> {:error, ["#{path} (#{module.type()}): children must be a list"]}
    end
  end

  defp parse_list(children, registry, path) do
    {nodes, errors} =
      children
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {child, index}, {nodes, errors} ->
        case parse_node(child, registry, "#{path}.children[#{index}]", false) do
          {:ok, node} -> {[node | nodes], errors}
          {:error, child_errors} -> {nodes, child_errors ++ errors}
        end
      end)

    if errors == [], do: {:ok, Enum.reverse(nodes)}, else: {:error, errors}
  end

  @doc """
  Returns the envelope of the document as a map.
  """
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{} = doc) do
    %{"kotoba" => doc.version, "lexical" => doc.lexical, "root" => Kotoba.Node.encode(doc.root)}
  end

  @doc """
  Calls `fun` on each node of the document, depth first, the parent before
  its children. Returns `:ok`.
  """
  @spec walk(t(), (Kotoba.Node.t() -> term())) :: :ok
  def walk(%__MODULE__{} = doc, fun) when is_function(fun, 1) do
    reduce(doc, :ok, fn node, :ok ->
      fun.(node)
      :ok
    end)
  end

  @doc """
  Reduces the nodes of the document, depth first, the parent before its
  children.

  ## Examples

      iex> {:ok, doc} = Kotoba.Document.parse(%{"kotoba" => 1, "lexical" => "0.51", "root" => %{"type" => "root"}})
      iex> Kotoba.Document.reduce(doc, 0, fn _node, count -> count + 1 end)
      1

  """
  @spec reduce(t(), acc, (Kotoba.Node.t(), acc -> acc)) :: acc when acc: term()
  def reduce(%__MODULE__{root: root}, acc, fun) when is_function(fun, 2),
    do: reduce_node(root, acc, fun)

  defp reduce_node(node, acc, fun) do
    acc = fun.(node, acc)
    node |> children() |> Enum.reduce(acc, &reduce_node(&1, &2, fun))
  end

  @doc """
  Returns a document with `fun` applied to each node, depth first.

  `fun` gets the parent before its children, and Kotoba then maps the
  children of the node that `fun` returns. `fun` gets the root node too,
  and must return a `Kotoba.Nodes.Root` for it.
  """
  @spec map(t(), (Kotoba.Node.t() -> Kotoba.Node.t())) :: t()
  def map(%__MODULE__{root: root} = doc, fun) when is_function(fun, 1) do
    %Root{} = root = map_node(root, fun)
    %{doc | root: root}
  end

  defp map_node(node, fun) do
    case fun.(node) do
      %{children: children} = mapped when is_list(children) ->
        %{mapped | children: Enum.map(children, &map_node(&1, fun))}

      mapped ->
        mapped
    end
  end

  @doc """
  Returns `true` when the document has no text other than white space and
  no node other than element, text and line break nodes.
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = doc) do
    reduce(doc, true, fn
      _node, false -> false
      %text{text: value}, true when text in [Text, CodeHighlight] -> String.trim(value) == ""
      %LineBreak{}, true -> true
      %Unknown{}, true -> false
      %module{}, true -> module.element?()
    end)
  end

  @doc """
  Returns the plain text of the document.

  Text runs in a block are joined. A line break gives `"\\n"`. A mention
  gives its label. Blocks are separated by `"\\n"`. Other nodes give no text.
  """
  @spec text(t()) :: String.t()
  def text(%__MODULE__{root: root}), do: node_text(root)

  defp node_text(%text{text: value}) when text in [Text, CodeHighlight], do: value
  defp node_text(%LineBreak{}), do: "\n"
  defp node_text(%Mention{label: label}), do: label
  defp node_text(%{children: children}) when is_list(children), do: children_text(children)
  defp node_text(_node), do: ""

  # Consecutive inline nodes make one segment; each block child is a segment.
  defp children_text(children) do
    children
    |> Enum.chunk_by(&block?/1)
    |> Enum.flat_map(fn
      [first | _rest] = chunk ->
        if block?(first),
          do: Enum.map(chunk, &node_text/1),
          else: [Enum.map_join(chunk, &node_text/1)]
    end)
    |> Enum.join("\n")
  end

  defp block?(%Unknown{}), do: false
  defp block?(%module{}), do: module.kind() == :block

  @doc """
  Returns the mention nodes of the document, in document order.
  """
  @spec mentions(t()) :: [Mention.t()]
  def mentions(%__MODULE__{} = doc), do: collect(doc, Mention)

  @doc """
  Returns the attachment nodes of the document, in document order.
  """
  @spec attachments(t()) :: [Attachment.t()]
  def attachments(%__MODULE__{} = doc), do: collect(doc, Attachment)

  defp collect(doc, module) do
    doc
    |> reduce([], fn
      %^module{} = node, acc -> [node | acc]
      _node, acc -> acc
    end)
    |> Enum.reverse()
  end

  defp children(%Unknown{}), do: []
  defp children(%{children: children}) when is_list(children), do: children
  defp children(_node), do: []
end
