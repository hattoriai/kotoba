defmodule Kotoba.Nodes do
  @moduledoc """
  The node registry.

  The registry maps each Lexical node type to the module that reads it. It
  has the built-in nodes, the nodes in the `:nodes` key of the `:kotoba`
  application config, and the nodes that the caller gives. A later entry
  replaces an earlier entry with the same type:

      config :kotoba, nodes: [MyApp.Nodes.Pointer]

  `Kotoba.Document.parse/2`, `Kotoba.Content.rerender/2` and
  `Kotoba.Components.kotoba_content/1` take the caller's nodes as a
  `nodes` option. `Kotoba.Content.cast/1` uses the built-in and the
  configured nodes only, so put a node that stored content uses in the
  config. `mix kotoba.gen.node` writes a new node module and its editor
  half.
  """

  alias Kotoba.Nodes

  @built_in [
    Nodes.Root,
    Nodes.Paragraph,
    Nodes.Heading,
    Nodes.Quote,
    Nodes.List,
    Nodes.ListItem,
    Nodes.Text,
    Nodes.Tab,
    Nodes.LineBreak,
    Nodes.Link,
    Nodes.AutoLink,
    Nodes.Code,
    Nodes.CodeHighlight,
    Nodes.HorizontalRule,
    Nodes.Attachment,
    Nodes.Mention
  ]

  @typedoc "A map from a node type to its module."
  @type registry :: %{String.t() => module()}

  @doc "Returns the built-in node modules."
  @spec built_in() :: [module()]
  def built_in, do: @built_in

  @doc """
  Returns the registry for a list of extra node modules.

  Raises `ArgumentError` when a module does not use `Kotoba.Node`.
  """
  @spec registry([module()]) :: registry()
  def registry(nodes \\ []) when is_list(nodes) do
    configured = Application.get_env(:kotoba, :nodes, [])

    Map.new(@built_in ++ configured ++ nodes, fn module ->
      unless Kotoba.Node.node_module?(module) do
        raise ArgumentError, "#{inspect(module)} is not a Kotoba.Node module"
      end

      {module.type(), module}
    end)
  end
end
