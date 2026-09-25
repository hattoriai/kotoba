defmodule KotobaTest.EditorLive do
  @moduledoc """
  A LiveView with a Kotoba editor, prompts and uploads, for the
  `Kotoba.Live` tests.

  The query param `storage` picks the adapter: `failing` for
  `KotobaTest.FailingStorage`, `unsafe` for `KotobaTest.UnsafeStorage`,
  `broken` for `KotobaTest.BrokenStorage`.
  """
  use Phoenix.LiveView

  import Kotoba.Components

  @editor "post_body_editor"

  def editor_id, do: @editor

  @impl true
  def mount(params, _session, socket) do
    storage =
      case params["storage"] do
        "failing" -> KotobaTest.FailingStorage
        "unsafe" -> KotobaTest.UnsafeStorage
        "broken" -> KotobaTest.BrokenStorage
        _other -> Kotoba.Storage.Local
      end

    {:ok,
     socket
     |> assign(
       storage: storage,
       form: to_form(%{"body" => nil}, as: :post)
     )
     |> allow_upload(:attachments,
       accept: ~w(.png .txt),
       max_entries: 3,
       max_file_size: 1_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.form for={@form} id="post-form" phx-change="validate">
      <label id="body-label">Body</label>
      <.kotoba
        field={@form[:body]}
        id={editor_id()}
        label_id="body-label"
        prompts={prompts()}
        uploads={@uploads.attachments}
      />
    </.form>
    """
  end

  defp prompts do
    [
      people: fn query ->
        [%{id: 1, label: "Ada Lovelace", hint: "Engineering"}, %{id: 2, label: "Grace Hopper"}]
        |> Enum.filter(&String.contains?(String.downcase(&1.label), String.downcase(query)))
      end,
      work: fn query, socket -> [{"w-#{socket.id}", "Work: #{query}"}] end
    ]
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply,
     Kotoba.Live.consume_uploads(socket, :attachments, @editor, storage: socket.assigns.storage)}
  end

  def handle_event("kotoba:prompt", params, socket) do
    {:noreply, Kotoba.Live.handle_prompt(socket, params, prompts())}
  end

  @impl true
  def handle_info({:push_content, content}, socket),
    do: {:noreply, Kotoba.Live.push_content(socket, @editor, content)}

  def handle_info({:insert_node, node}, socket),
    do: {:noreply, Kotoba.Live.insert_node(socket, @editor, node)}

  def handle_info({:set_readonly, readonly}, socket),
    do: {:noreply, Kotoba.Live.set_readonly(socket, @editor, readonly)}

  def handle_info(:focus, socket), do: {:noreply, Kotoba.Live.focus(socket, @editor)}

  def handle_info({:remove_marker, ref}, socket),
    do: {:noreply, Kotoba.Live.remove_marker(socket, @editor, ref)}

  defp handle_progress(:attachments, entry, socket) do
    if entry.done? do
      {:noreply,
       Kotoba.Live.consume_uploads(socket, :attachments, @editor, storage: socket.assigns.storage)}
    else
      {:noreply, socket}
    end
  end
end

defmodule KotobaTest.FailingStorage do
  @moduledoc "A `Kotoba.Storage` adapter that fails every `put/3`."
  @behaviour Kotoba.Storage

  @impl true
  def put(_key, _path, _meta), do: {:error, :disk_full}

  @impl true
  def url(key), do: "/failing/" <> key

  @impl true
  def delete(_key), do: :ok
end

defmodule KotobaTest.UnsafeStorage do
  @moduledoc "A `Kotoba.Storage` adapter that returns a URL that is not a safe link."
  @behaviour Kotoba.Storage

  @impl true
  def put(_key, _path, _meta), do: {:ok, "javascript:alert(1)"}

  @impl true
  def url(_key), do: "javascript:alert(1)"

  @impl true
  def delete(_key), do: :ok
end

defmodule KotobaTest.BrokenStorage do
  @moduledoc "A `Kotoba.Storage` adapter whose `put/3` breaks its contract."
  @behaviour Kotoba.Storage

  @impl true
  def put(_key, _path, _meta), do: {:ok, nil}

  @impl true
  def url(key), do: key

  @impl true
  def delete(_key), do: :ok
end
