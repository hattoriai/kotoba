defmodule Kotoba.Node.Override do
  @moduledoc """
  Another rendering of a node of Kotoba (or of an app): its HTML, text or
  Markdown, as TipTap's `extend` of a node.

  The node stays the same: the same type, the same JSON and the same
  struct. An override only renders it. A callback that the override does
  not define renders as the node does. The editor half of the change (its
  own state on the node, its DOM) is an extension; see the
  [Extensions](extensions.md) guide.

      defmodule MyApp.Links do
        use Kotoba.Node.Override, of: Kotoba.Nodes.Link

        # A link to a page of the app goes to where the page is now, or is
        # only its text when the page is gone.
        @impl Kotoba.Node.Override
        def render_html(node, opts) do
          case MyApp.Pages.link_url(node.url) do
            :not_ours -> Kotoba.Nodes.Link.render_html(node, opts)
            nil -> Kotoba.Renderer.html_children(node, opts)
            url -> Kotoba.Nodes.Link.render_html(%{node | url: url}, opts)
          end
        end
      end

  An override applies when it is in the `:overrides` key of the `:kotoba`
  application config (then also in the HTML that `Kotoba.Content` keeps),
  or in the `overrides` option of `Kotoba.Renderer`, `Kotoba.Content.rerender/2`
  and `Kotoba.Components.kotoba_content/1`. A caller's override of a node
  replaces the configured one.

      config :kotoba, overrides: [MyApp.Links]

  The HTML of an override is not sanitized again: render the app's data
  with HEEx (`~H`) or `Kotoba.Renderer.tag/3`, which escape it. The render
  options (`opts`) have what the renderer was given (the caller's own
  options too), so an override can take its data from them:

      Kotoba.Content.rerender(content, overrides: [MyApp.Links], site: :public)

  ## The node's state

  An extension can keep its own values on a node of the editor (Lexical's
  NodeState). They are in the node's JSON under `"$"`; `state/3` reads one.
  """

  @doc "The node module that this module renders."
  @callback of() :: module()

  @doc "The HTML of the node."
  @callback render_html(node :: Kotoba.Node.t(), opts :: keyword()) ::
              Phoenix.HTML.safe() | Phoenix.LiveView.Rendered.t()

  @doc "The plain text of the node."
  @callback render_text(node :: Kotoba.Node.t(), opts :: keyword()) :: String.t()

  @doc "The Markdown of the node."
  @callback render_markdown(node :: Kotoba.Node.t(), opts :: keyword()) :: String.t()

  @doc false
  defmacro __using__(opts) do
    of = Keyword.fetch!(opts, :of)

    quote do
      @behaviour Kotoba.Node.Override

      @impl Kotoba.Node.Override
      def of, do: unquote(of)

      @impl Kotoba.Node.Override
      def render_html(node, opts), do: unquote(of).render_html(node, opts)

      @impl Kotoba.Node.Override
      def render_text(node, opts), do: unquote(of).render_text(node, opts)

      @impl Kotoba.Node.Override
      def render_markdown(node, opts), do: unquote(of).render_markdown(node, opts)

      defoverridable render_html: 2, render_text: 2, render_markdown: 2
    end
  end

  @doc """
  Returns a value of the node's state (Lexical's NodeState, under `"$"` in
  its JSON), or `default`.

      Kotoba.Node.Override.state(link, "target")
      #=> "_blank"
  """
  @spec state(Kotoba.Node.t(), String.t(), term()) :: term()
  def state(node, key, default \\ nil)

  def state(%{extra: %{"$" => %{} = state}}, key, default) when is_binary(key),
    do: Map.get(state, key, default)

  def state(_node, _key, default), do: default

  @doc """
  Returns the map of the overrides: the configured ones, then the given
  ones, from each node module to its override. Raises `ArgumentError` for a
  module that is not an override of a node module.
  """
  @spec registry([module()]) :: %{module() => module()}
  def registry(overrides \\ []) when is_list(overrides) do
    configured = Application.get_env(:kotoba, :overrides, [])

    Map.new(configured ++ overrides, fn module ->
      unless override?(module) do
        raise ArgumentError,
              "#{inspect(module)} is not a Kotoba.Node.Override (use Kotoba.Node.Override, of: ...)"
      end

      node = module.of()

      unless Kotoba.Node.node_module?(node) do
        raise ArgumentError,
              "#{inspect(module)} overrides #{inspect(node)}, which is not a Kotoba.Node module"
      end

      {node, module}
    end)
  end

  defp override?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :of, 0) and
      function_exported?(module, :render_html, 2)
  end

  defp override?(_other), do: false
end
