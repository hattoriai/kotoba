defmodule Kotoba.Embeds do
  @moduledoc """
  The LiveComponent behind `Kotoba.Components.kotoba_embeds/1`: the live
  content of an editor's embeds (`Kotoba.Nodes.Embed`).

  Render it with `kotoba_embeds/1`, not with this module. An editor with
  `embeds` tells it, with `"kotoba:embeds"` events, when an embed's slot
  comes and goes (`"mount"` with the slot's id and the embed's `kind`,
  `ref` and `title`; `"unmount"`), and when a person asks to insert one
  (`"picker"`). The component renders the app's `:embed` slot for each
  embed, and LiveView teleports it into the embed's slot in the document
  (a portal), so that the content is the LiveView's own: its events, its
  LiveComponents (a canvas, a grid) and its updates, in the document.

  It also keeps which embed is full screen: the content then goes, as it
  is, into a layer over the page, and back.

  See the [Embeds](embeds.md) guide.
  """
  use Phoenix.LiveComponent

  alias Phoenix.LiveView.JS

  @impl true
  def mount(socket), do: {:ok, assign(socket, embeds: %{}, full: nil, picker: false)}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    # A read-only editor inserts nothing.
    socket = if socket.assigns[:readonly], do: assign(socket, :picker, false), else: socket
    {:ok, socket}
  end

  @impl true
  def handle_event("kotoba:embeds", %{"action" => "mount", "slot" => slot} = params, socket)
      when is_binary(slot) do
    if own_slot?(socket, slot) do
      embed = %{
        id: slot,
        kind: string(params["kind"]),
        ref: string(params["ref"]),
        title: string(params["title"])
      }

      {:noreply, update(socket, :embeds, &Map.put(&1, slot, embed))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("kotoba:embeds", %{"action" => "unmount", "slot" => slot}, socket) do
    socket = update(socket, :embeds, &Map.delete(&1, slot))
    {:noreply, if(socket.assigns.full == slot, do: assign(socket, :full, nil), else: socket)}
  end

  def handle_event("kotoba:embeds", %{"action" => "picker"}, socket) do
    {:noreply,
     assign(socket, :picker, socket.assigns.picker_slot != [] and !socket.assigns.readonly)}
  end

  def handle_event("kotoba:embeds", _params, socket), do: {:noreply, socket}

  def handle_event("close_picker", _params, socket),
    do: {:noreply, assign(socket, :picker, false)}

  def handle_event("full", %{"slot" => slot}, socket) do
    full =
      if socket.assigns.full == slot or not Map.has_key?(socket.assigns.embeds, slot),
        do: nil,
        else: slot

    {:noreply, assign(socket, :full, full)}
  end

  def handle_event("restore", _params, socket), do: {:noreply, assign(socket, :full, nil)}

  # The editor's slots are `<editor id>-embed-<key>`.
  defp own_slot?(socket, slot), do: String.starts_with?(slot, socket.assigns.for <> "-embed-")

  defp string(value) when is_binary(value), do: value
  defp string(_value), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class={["kotoba-embeds", @class]}
      data-for={@for}
      data-label={@label}
      data-icon={@icon}
      data-picker={to_string(@picker_slot != [])}
    >
      <.portal
        :for={{slot, embed} <- @embeds}
        :key={slot}
        id={@id <> "-portal-" <> slot}
        target={if @full == slot, do: "#" <> @id <> "-full-body", else: "#" <> slot}
        class="kotoba-embed-content"
      >
        {render_slot(@embed, embed_assigns(embed, assigns))}
      </.portal>

      <div
        id={@id <> "-full"}
        class="kotoba-embed-full"
        hidden={is_nil(@full)}
        phx-window-keydown={@full && JS.push("restore", target: @myself)}
        phx-key="Escape"
      >
        <div class="kotoba-embed-scrim" phx-click="restore" phx-target={@myself}></div>
        <div
          id={@id <> "-full-body"}
          class="kotoba-embed-full-body"
          role="dialog"
          aria-modal="true"
          aria-label={@full && @embeds[@full] && @embeds[@full].title}
        >
        </div>
      </div>

      <div
        :if={@picker}
        id={@id <> "-picker"}
        class="kotoba-embed-picker-layer"
        phx-window-keydown={JS.push("close_picker", target: @myself)}
        phx-key="Escape"
      >
        <div class="kotoba-embed-scrim" phx-click="close_picker" phx-target={@myself}></div>
        <div
          class="kotoba-embed-picker"
          role="dialog"
          aria-modal="true"
          aria-labelledby={@id <> "-picker-title"}
          phx-mounted={JS.focus_first(to: "#" <> @id <> "-picker-body")}
        >
          <div class="kotoba-embed-picker-head">
            <span id={@id <> "-picker-title"}>{@picker_title}</span>
            <button
              type="button"
              class="kotoba-embed-picker-close"
              aria-label="Close"
              phx-click="close_picker"
              phx-target={@myself}
            >
              <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
                <path d="M18 6 6 18" /><path d="m6 6 12 12" />
              </svg>
            </button>
          </div>
          <div id={@id <> "-picker-body"} class="kotoba-embed-picker-body">
            {render_slot(@picker_slot, %{editor: @for, close: JS.push("close_picker", target: @myself)})}
          </div>
        </div>
      </div>
    </div>
    """
  end

  # What the app's `:embed` slot gets for an embed.
  defp embed_assigns(embed, assigns) do
    Map.merge(embed, %{
      editor: assigns.for,
      full: assigns.full == embed.id,
      readonly: assigns.readonly,
      toggle_full: JS.push("full", target: assigns.myself, value: %{slot: embed.id})
    })
  end
end
