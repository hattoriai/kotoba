defmodule Kotoba.Sanitizer do
  @moduledoc """
  The structural checks that `Kotoba.Renderer` does before it renders a
  node.

  Kotoba never passes raw HTML through. The renderer escapes every string,
  and the sanitizer adds these checks:

    * **Attributes.** The node must pass its own `validate/1`. Each string
      attribute must have no control characters, and its length must be in
      the limit: 200 characters for `label`, `name`, `title`, `kind`, `id`,
      `rel`, `target`, `language` and `content_type`, and 2048 characters
      for the other string attributes, `url` included. The text of a `Kotoba.Nodes.Text` or
      `Kotoba.Nodes.CodeHighlight` node and the `style` of a text node are
      not attributes; they have no limit. The URL of a link is checked by
      `link_url/2`.
    * **Nesting.** A list holds only list items. A list item holds inline
      nodes, decorators and one nested list. A code block holds only
      code highlight, text and line break nodes. A paragraph, a heading, a
      quote and a link hold only inline nodes and decorators, and a link
      holds no other link. A decorator has no children.
    * **Links.** `link_url/2` accepts a URL with an allowed scheme, or a
      relative URL. A link with a URL that is not safe renders as its text.
      An attachment with a URL that is not safe fails the check.

  When a node fails a check, the renderer renders it as an unknown node
  (inert, with no content). It does not raise.

  ## Link schemes

  The allowed schemes come from the application config. The default is
  `~w(http https mailto)`:

      config :kotoba, allowed_link_schemes: ~w(http https mailto tel)

  ## Policies

    * `:default` - links render as anchors and attachments render as
      figures.
    * `:untrusted` - for content from people that the app does not trust.
      Links render as their text, with no anchor. Attachments render as
      their file name, with no image and no link.
  """

  alias Kotoba.Nodes

  @typedoc "The name of a policy."
  @type policy_name :: :default | :untrusted

  @typedoc """
  A policy. `links` is `true` when links render as anchors. `attachments`
  is `true` when attachments render as figures.
  """
  @type policy :: %{name: policy_name(), links: boolean(), attachments: boolean()}

  @default_schemes ~w(http https mailto)
  @url_limit 2048
  @label_limit 200
  @label_fields [:label, :name, :title, :kind, :id, :rel, :target, :language, :content_type]

  @control ~r/[\x{0000}-\x{001F}\x{007F}-\x{009F}]/u
  @scheme ~r/\A([a-zA-Z][a-zA-Z0-9+.\-]*):/

  @doc """
  Returns the policy for a name. A policy map is returned with no change.

  Raises `ArgumentError` for an unknown name.

  ## Examples

      iex> Kotoba.Sanitizer.policy(:untrusted)
      %{name: :untrusted, links: false, attachments: false}

  """
  @spec policy(policy_name() | policy()) :: policy()
  def policy(:default), do: %{name: :default, links: true, attachments: true}
  def policy(:untrusted), do: %{name: :untrusted, links: false, attachments: false}

  def policy(%{name: _name, links: links, attachments: attachments} = policy)
      when is_boolean(links) and is_boolean(attachments),
      do: policy

  def policy(other),
    do: raise(ArgumentError, "unknown policy #{inspect(other)}, use :default or :untrusted")

  @doc """
  Returns the URL for an `href` or a `src`, or `nil` when it is not safe.

  The URL is trimmed. It is accepted when it has a scheme from the allowed
  schemes, or when it has no scheme (a relative URL). A URL with a control
  character, or with more than 2048 characters, is refused.

  ## Options

    * `:schemes` - the allowed schemes. The default comes from
      `config :kotoba, allowed_link_schemes:`, else `~w(http https mailto)`.

  ## Examples

      iex> Kotoba.Sanitizer.link_url("https://example.com")
      "https://example.com"

      iex> Kotoba.Sanitizer.link_url("/docs#top")
      "/docs#top"

      iex> Kotoba.Sanitizer.link_url("javascript:alert(1)")
      nil

  """
  @spec link_url(term(), keyword()) :: String.t() | nil
  def link_url(url, opts \\ [])

  def link_url(url, opts) when is_binary(url) and is_list(opts) do
    url = String.trim(url)

    cond do
      url == "" -> nil
      String.length(url) > @url_limit -> nil
      Regex.match?(@control, url) -> nil
      true -> check_scheme(url, opts)
    end
  end

  def link_url(_url, _opts), do: nil

  defp check_scheme(url, opts) do
    case Regex.run(@scheme, url, capture: :all_but_first) do
      nil -> url
      [scheme] -> if String.downcase(scheme) in schemes(opts), do: url
    end
  end

  defp schemes(opts) do
    opts
    |> Keyword.get_lazy(:schemes, fn ->
      Application.get_env(:kotoba, :allowed_link_schemes, @default_schemes)
    end)
    |> Enum.map(&String.downcase/1)
  end

  @doc """
  Checks one node in its parent. `parent` is `nil` for the root node. The
  `:schemes` option is the same as in `link_url/2`.

  Returns `:ok`, or `{:error, reason}` when the renderer must render the
  node as an unknown node.
  """
  @spec check(Kotoba.Node.t(), Kotoba.Node.t() | nil, keyword()) :: :ok | {:error, String.t()}
  def check(node, parent, opts \\ [])

  def check(%Nodes.Unknown{}, _parent, _opts), do: :ok

  def check(%module{} = node, parent, opts) do
    with :ok <- check_valid(module, node),
         :ok <- check_strings(module, node),
         :ok <- check_children(module, node),
         :ok <- check_url(node, opts) do
      check_parent(node, parent)
    end
  end

  defp check_url(%Nodes.Attachment{url: url}, opts) do
    if link_url(url, opts), do: :ok, else: {:error, "url is not a safe URL"}
  end

  defp check_url(_node, _opts), do: :ok

  defp check_valid(module, node) do
    case module.validate(node) do
      :ok -> :ok
      {:error, [message | _rest]} -> {:error, message}
    end
  end

  defp check_strings(module, node) do
    Enum.reduce_while(module.fields(), :ok, fn field, :ok ->
      case check_string(module, field, Map.fetch!(node, field.name)) do
        :ok -> {:cont, :ok}
        {:error, _message} = error -> {:halt, error}
      end
    end)
  end

  defp check_string(module, field, _value)
       when module in [Nodes.Text, Nodes.CodeHighlight] and field.name in [:text, :style],
       do: :ok

  # `link_url/2` checks the URL of a link; a link with a bad URL keeps its text.
  defp check_string(module, field, _value)
       when module in [Nodes.Link, Nodes.AutoLink] and field.name == :url,
       do: :ok

  defp check_string(module, field, values) when is_list(values) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case check_string(module, field, value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp check_string(_module, field, value) when is_binary(value) do
    cond do
      Regex.match?(@control, value) ->
        {:error, "#{field.key} has a control character"}

      String.length(value) > limit(field.name) ->
        {:error, "#{field.key} is longer than #{limit(field.name)} characters"}

      true ->
        :ok
    end
  end

  defp check_string(_module, _field, _value), do: :ok

  defp limit(name) when name in @label_fields, do: @label_limit
  defp limit(_name), do: @url_limit

  defp check_children(module, node) do
    if module.kind() == :decorator and Map.get(node, :children, []) != [],
      do: {:error, "a decorator has no children"},
      else: :ok
  end

  defp check_parent(_node, nil), do: :ok
  defp check_parent(%Nodes.ListItem{}, %Nodes.List{}), do: :ok
  defp check_parent(_node, %Nodes.List{}), do: {:error, "a list holds only list items"}

  defp check_parent(%Nodes.List{} = node, %Nodes.ListItem{children: children}) do
    case Enum.find(children, &match?(%Nodes.List{}, &1)) do
      ^node -> :ok
      _other -> {:error, "a list item holds only one nested list"}
    end
  end

  defp check_parent(%module{}, %Nodes.Code{}) do
    if module in [Nodes.CodeHighlight, Nodes.Text, Nodes.LineBreak],
      do: :ok,
      else: {:error, "a code block holds only code, text and line breaks"}
  end

  defp check_parent(%link{}, %parent{})
       when link in [Nodes.Link, Nodes.AutoLink] and parent in [Nodes.Link, Nodes.AutoLink],
       do: {:error, "a link holds no other link"}

  defp check_parent(%module{}, %parent{})
       when parent in [
              Nodes.ListItem,
              Nodes.Paragraph,
              Nodes.Heading,
              Nodes.Quote,
              Nodes.Link,
              Nodes.AutoLink
            ] do
    if module.kind() == :block,
      do: {:error, "a #{parent.type()} node holds only inline nodes and decorators"},
      else: :ok
  end

  defp check_parent(_node, _parent), do: :ok
end
