defmodule KotobaTest.EmbedsLive do
  @moduledoc "A LiveView with an editor that has embeds, for the embeds tests."
  use Phoenix.LiveView

  import Kotoba.Components

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       form: to_form(%{"body" => nil}, as: :post),
       readonly: params["readonly"] == "true",
       picker: params["picker"] != "false"
     )}
  end

  @impl true
  def handle_event("insert_counter", %{"ref" => ref}, socket),
    do:
      {:noreply,
       Kotoba.Live.insert_embed(socket, "body", "counter", ref, title: "Counter #{ref}")}

  # Links to this app's counters.
  def resolve("https://app.test/counters/" <> id),
    do: %{kind: "counter", ref: id, title: "Counter #{id}"}

  def resolve(_url), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <.form for={@form} id="post">
      <.kotoba field={@form[:body]} id="body" embeds readonly={@readonly} />
    </.form>
    <.kotoba_embeds :if={@picker} for="body" label="Counter" icon="chart" readonly={@readonly} resolve={&resolve/1}>
      <:embed :let={embed}>
        <div class="counter" id={"counter-" <> embed.id} data-full={to_string(embed.full)}>
          {embed.kind}:{embed.ref} {embed.title}
          <button class="full" phx-click={embed.toggle_full}>Full screen</button>
          <span :if={embed.readonly} class="readonly">read-only</span>
        </div>
      </:embed>
      <:picker :let={picker}>
        <.kotoba_embed_option phx-click="insert_counter" phx-value-ref="9" title="Counter 9" about="Counts">
          <:icon>#</:icon>
        </.kotoba_embed_option>
        <button class="cancel" phx-click={picker.close}>Cancel</button>
      </:picker>
    </.kotoba_embeds>
    <.kotoba_embeds :if={!@picker} for="body">
      <:embed :let={embed}>{embed.ref}</:embed>
    </.kotoba_embeds>
    """
  end
end
