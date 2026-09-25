defmodule Kotoba.Components do
  @moduledoc """
  Function components for the Kotoba editor and for rendered content.

      import Kotoba.Components

      <.form for={@form} phx-change="validate" phx-submit="save">
        <label id="post-body-label">Body</label>
        <.kotoba field={@form[:body]} id="post-body" label_id="post-body-label" />
      </.form>

      <.kotoba_content content={@post.body} />

  The editor needs the `Kotoba` hook in the LiveSocket and the Kotoba CSS
  (see the README).
  """

  use Phoenix.Component

  alias Kotoba.{Content, Document, Prompts, Renderer, Sanitizer}
  alias Phoenix.HTML.FormField

  @commands [
    {"bold", "Bold", "Text"},
    {"italic", "Italic", "Text"},
    {"strikethrough", "Strikethrough", "Text"},
    {"code", "Inline code", "Text"},
    {"link", "Link", "Text"},
    {"h1", "Heading 1", "Blocks"},
    {"h2", "Heading 2", "Blocks"},
    {"h3", "Heading 3", "Blocks"},
    {"h4", "Heading 4", "Blocks"},
    {"quote", "Quote", "Blocks"},
    {"bullet", "Bulleted list", "Lists"},
    {"number", "Numbered list", "Lists"},
    {"check", "Check list", "Lists"},
    {"code-block", "Code block", "Insert"},
    {"rule", "Horizontal rule", "Insert"},
    {"upload", "Attach a file", "Insert"},
    {"undo", "Undo", "History"},
    {"redo", "Redo", "History"}
  ]

  @command_names Enum.map(@commands, &elem(&1, 0))

  @doc """
  Returns the names of the toolbar commands, in toolbar order.

  ## Examples

      iex> "bold" in Kotoba.Components.toolbar_commands()
      true

  """
  @spec toolbar_commands() :: [String.t()]
  def toolbar_commands, do: @command_names

  @doc """
  Renders the rich-text editor for a form field.

  It renders:

    * a hidden input with the field's `name` and, as its value, the JSON of
      the field's value cast to `Kotoba.Content` (or of an empty document).
      The editor writes the document to it on every change, so a plain
      form submit posts it. It is outside the editor element, so a
      LiveView patch can update it;
    * the editor element, with `phx-hook="Kotoba"` and `phx-update="ignore"`.
      The hook builds the toolbar and the editable area in it;
    * the LiveView file input of `uploads`, visually hidden, when
      `uploads` is given. The toolbar's attach button, a drop and a paste
      of files hand the files to it.

  Attributes that are not declared (`phx-target`, `aria-describedby`, …) go
  on the editor element. In a LiveComponent, give `phx-target={@myself}`,
  so that the editor's events go to the component.

  A change of `readonly` in a later render reaches the editor. To change
  the document after the first render, use `Kotoba.Live.push_content/3`:
  the editor reads the hidden input only when it mounts.
  """
  attr :field, FormField, required: true, doc: "the form field, for example `@form[:body]`"

  attr :id, :string,
    default: nil,
    doc: "the id of the editor element. The default is the field's id with `_editor`"

  attr :label_id, :string,
    default: nil,
    doc: "the id of the element that labels the editor (`aria-labelledby`)"

  attr :placeholder, :string, default: nil, doc: "the text of an empty editor"

  attr :nodes, :list,
    default: [],
    doc: "app nodes: `{module, js_url}` tuples, or JavaScript module URLs"

  attr :prompts, :list, default: [], doc: "the prompt list, see `Kotoba.Prompts`"

  attr :uploads, Phoenix.LiveView.UploadConfig,
    default: nil,
    doc: "an upload config, for example `@uploads.attachments`"

  attr :upload_label, :string, default: "Attach files", doc: "the label of the file input"
  attr :readonly, :boolean, default: false
  attr :debounce, :integer, default: nil, doc: "milliseconds between `kotoba:change` pushes"
  attr :class, :any, default: nil, doc: "classes for the wrapper element"
  attr :rest, :global, doc: "attributes for the editor element"

  slot :toolbar,
    doc:
      "a custom toolbar, for example `<.kotoba_toolbar>`; the default toolbar has every command"

  def kotoba(assigns) do
    %FormField{} = field = assigns.field
    input_id = field.id
    id = assigns.id || "#{field.id}_editor"

    assigns =
      assign(assigns,
        id: id,
        input_id: input_id,
        value: field_json(field.value),
        node_urls: node_urls(assigns.nodes),
        triggers: triggers_json(assigns.prompts),
        link_schemes: Enum.join(Sanitizer.allowed_schemes(), ","),
        upload_id: assigns.uploads && assigns.uploads.ref
      )

    ~H"""
    <div class={["kotoba-field" | List.wrap(@class)]}>
      <input type="hidden" id={@input_id} name={@field.name} value={@value} />
      <div
        id={@id}
        phx-hook="Kotoba"
        phx-update="ignore"
        data-input={@input_id}
        data-readonly={to_string(@readonly)}
        data-placeholder={@placeholder}
        data-nodes={@node_urls}
        data-prompts={@triggers}
        data-upload={@upload_id}
        data-debounce={@debounce}
        data-link-schemes={@link_schemes}
        aria-labelledby={@label_id}
        {@rest}
      >
        {render_slot(@toolbar)}
      </div>
      <div :if={@uploads} class="kotoba-visually-hidden">
        <label for={@upload_id}>{@upload_label}</label>
        <.live_file_input upload={@uploads} tabindex="-1" />
      </div>
    </div>
    """
  end

  defp field_json(value) do
    doc =
      case Content.cast(value) do
        {:ok, %Content{doc: doc}} -> doc
        :error -> Content.empty().doc
      end

    JSON.encode!(doc)
  end

  defp node_urls([]), do: nil

  defp node_urls(nodes) do
    Enum.map_join(nodes, ",", fn
      {module, url} when is_atom(module) and is_binary(url) ->
        url

      url when is_binary(url) ->
        url

      other ->
        raise ArgumentError, "a Kotoba node must be {module, js_url}, got: #{inspect(other)}"
    end)
  end

  defp triggers_json(prompts) do
    case Prompts.triggers(prompts) do
      map when map_size(map) == 0 -> nil
      map -> JSON.encode!(map)
    end
  end

  @doc """
  Renders a custom toolbar for an editor.

  Inside the `toolbar` slot of `kotoba/1`, it needs no `for`. Elsewhere on
  the page, give the editor's id as `for`: the toolbar then has
  `phx-update="ignore"` (and the id `<for>-toolbar`), so that a LiveView
  patch does not undo the state that the editor puts on its buttons.

  With no `button` slots, it renders one text button for each of
  `commands`. With `button` slots, it renders them, for example with the
  app's own icons:

      <.kotoba_toolbar for="post-body">
        <:button command="bold"><.icon name="hero-bold" /></:button>
        <:button command="link" label="Add a link"><.icon name="hero-link" /></:button>
      </.kotoba_toolbar>

  The editor adds `role="toolbar"`, the roving tabindex, `aria-pressed`
  and `aria-disabled`. The commands are the ones of `toolbar_commands/0`;
  another command raises `ArgumentError`.
  """
  attr :for, :string, default: nil, doc: "the id of the editor, when the toolbar is outside it"
  attr :commands, :list, default: @command_names, doc: "the commands, when there are no buttons"
  attr :label, :string, default: "Formatting", doc: "the accessible name of the toolbar"
  attr :class, :any, default: nil
  attr :rest, :global

  slot :button do
    attr :command, :string, required: true
    attr :label, :string
    attr :class, :any
  end

  def kotoba_toolbar(assigns) do
    buttons =
      case assigns.button do
        [] ->
          Enum.map(assigns.commands, &%{command: command!(&1), label: label(&1), slot: nil})

        slots ->
          Enum.map(slots, fn slot ->
            command = command!(slot.command)
            %{command: command, label: slot[:label] || label(command), slot: slot}
          end)
      end

    assigns =
      assign(assigns,
        buttons: buttons,
        toolbar_id: assigns.for && "#{assigns.for}-toolbar"
      )

    ~H"""
    <div
      id={@toolbar_id}
      data-kotoba-toolbar={@for || ""}
      phx-update={@for && "ignore"}
      aria-label={@label}
      class={["kotoba-toolbar" | List.wrap(@class)]}
      {@rest}
    >
      <button
        :for={button <- @buttons}
        type="button"
        class={["kotoba-toolbar-button" | List.wrap(button.slot && button.slot[:class])]}
        data-kotoba-command={button.command}
        aria-label={button.slot && button.label}
        title={button.label}
      >
        {if button.slot, do: render_slot(button.slot), else: button.label}
      </button>
    </div>
    """
  end

  defp command!(command) when command in @command_names, do: command

  defp command!(command) do
    raise ArgumentError,
          "unknown Kotoba toolbar command #{inspect(command)}, use one of #{inspect(@command_names)}"
  end

  for {command, label, _group} <- @commands do
    defp label(unquote(command)), do: unquote(label)
  end

  @doc """
  Renders a `Kotoba.Content` as safe HTML.

  The cached `:html` of the content is used when its cache version is the
  current one (`Kotoba.Content.cache_version/0`), the policy is `:default`
  and no extra `nodes` are given: this is the HTML that `Kotoba.Renderer`
  made when the content was cast. In every other case, the document is
  rendered again with `Kotoba.Renderer` (a document that no longer parses
  renders as nothing). `nil` renders an empty wrapper.
  """
  attr :content, :any, required: true, doc: "a `Kotoba.Content`, or `nil`"

  attr :policy, :any,
    default: :default,
    doc: "`:default` or `:untrusted`, see `Kotoba.Sanitizer`"

  attr :nodes, :list, default: [], doc: "extra node modules, or `{module, js_url}` tuples"
  attr :class, :any, default: nil
  attr :rest, :global

  def kotoba_content(assigns) do
    assigns =
      assign(
        assigns,
        :html,
        content_html(assigns.content, assigns.policy, modules(assigns.nodes))
      )

    ~H"""
    <div class={["kotoba-content" | List.wrap(@class)]} {@rest}>{@html}</div>
    """
  end

  defp content_html(nil, _policy, _nodes), do: ""

  defp content_html(%Content{} = content, policy, nodes) do
    if cached?(content, policy, nodes),
      do: {:safe, content.html},
      else: render_doc(content.doc, policy, nodes)
  end

  defp content_html(other, _policy, _nodes) do
    raise ArgumentError, "kotoba_content needs a Kotoba.Content or nil, got: #{inspect(other)}"
  end

  defp cached?(%Content{html: html, version: version}, policy, nodes) do
    is_binary(html) and version == Content.cache_version() and nodes == [] and
      Sanitizer.policy(policy) == Sanitizer.policy(:default)
  end

  defp render_doc(doc, policy, nodes) do
    case Document.parse(doc, nodes: nodes) do
      {:ok, parsed} -> Renderer.to_html(parsed, policy: policy)
      {:error, _messages} -> ""
    end
  end

  defp modules(nodes) do
    Enum.map(nodes, fn
      {module, _url} when is_atom(module) -> module
      module when is_atom(module) -> module
    end)
  end
end
