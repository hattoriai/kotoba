defmodule KotobaTest.EditorLive do
  @moduledoc """
  A LiveView with a Kotoba editor, prompts and uploads, for the
  `Kotoba.Live` tests.

  The query param `storage` picks the adapter: `failing` for
  `KotobaTest.FailingStorage`, `unsafe` for `KotobaTest.UnsafeStorage`,
  `broken` for `KotobaTest.BrokenStorage`. These three adapters send
  `{:deleted, key}` to the process registered as `:kotoba_storage_test`
  when `delete/1` is called.
  """
  use Phoenix.LiveView

  import Kotoba.Components

  @editor "post_body_editor"

  def editor_id, do: @editor

  @doc "Sends `{:deleted, key}` to the `:kotoba_storage_test` process, if there is one."
  def report_delete(key) do
    case Process.whereis(:kotoba_storage_test) do
      nil -> :ok
      pid -> send(pid, {:deleted, key})
    end

    :ok
  end

  @impl true
  def mount(params, _session, socket) do
    storage = storage(params["storage"])
    preview = preview(params["preview"])

    {:ok,
     socket
     |> assign(
       storage: storage,
       preview: preview,
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

  defp storage("failing"), do: KotobaTest.FailingStorage
  defp storage("unsafe"), do: KotobaTest.UnsafeStorage
  defp storage("broken"), do: KotobaTest.BrokenStorage
  defp storage(_other), do: Kotoba.Storage.Local

  # ?preview=ok gives each upload a preview URL, ?preview=unsafe an unsafe
  # one, ?preview=raise an exception.
  defp preview("ok"), do: &ok_preview/2
  defp preview("unsafe"), do: fn _node, _path -> "javascript:alert(1)" end
  defp preview("raise"), do: fn _node, _path -> raise "no renderer" end
  defp preview(_other), do: nil

  defp ok_preview(node, path), do: if(File.exists?(path), do: "/previews/#{node.name}.jpg")

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
      {"@", :people,
       fn query ->
         [%{id: 1, label: "Ada Lovelace", hint: "Engineering"}, %{id: 2, label: "Grace Hopper"}]
         |> Enum.filter(&String.contains?(String.downcase(&1.label), String.downcase(query)))
       end},
      {"#", :work, fn query, socket -> [{"w-#{socket.id}", "Work: #{query}"}] end},
      {"!", :broken, fn _query -> raise "the search is down" end},
      {"+", :slow, [search: &slow_search/1, async: true, spaces: true]},
      {"~", :slow_broken,
       [search: fn _query -> raise "the slow search is down" end, async: true]},
      {":", :emoji, [items: [%{id: "tada", label: "tada", text: "🎉"}], insert: :text]}
    ]
  end

  # A search that reports its process: the test checks that it does not run
  # in the LiveView's.
  defp slow_search(query), do: [%{id: inspect(self()), label: "Slow: #{query}"}]

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply,
     Kotoba.Live.consume_uploads(socket, :attachments, @editor, storage: socket.assigns.storage)}
  end

  def handle_event("kotoba:prompt", params, socket) do
    {:noreply, Kotoba.Live.handle_prompt(socket, params, prompts())}
  end

  @impl true
  def handle_async({:kotoba_prompt, _id, _prompt, _query} = name, result, socket) do
    {:noreply, Kotoba.Live.handle_prompt_async(socket, name, result)}
  end

  @impl true
  def handle_info({:push_content, content}, socket),
    do: {:noreply, Kotoba.Live.push_content(socket, @editor, content)}

  def handle_info({:insert_node, node}, socket),
    do: {:noreply, Kotoba.Live.insert_node(socket, @editor, node)}

  def handle_info({:set_readonly, readonly}, socket),
    do: {:noreply, Kotoba.Live.set_readonly(socket, @editor, readonly)}

  def handle_info(:focus, socket), do: {:noreply, Kotoba.Live.focus(socket, @editor)}

  def handle_info({:stream, function, args}, socket),
    do: {:noreply, apply(Kotoba.Live, function, [socket, @editor | args])}

  # The result of an async search, as handle_async/3 gets it (an exit
  # cannot come from a real search: Kotoba.Prompts.search/3 catches it).
  def handle_info({:async_result, name, result}, socket),
    do: {:noreply, Kotoba.Live.handle_prompt_async(socket, name, result)}

  def handle_info({:remove_marker, ref}, socket),
    do: {:noreply, Kotoba.Live.remove_marker(socket, @editor, ref)}

  defp handle_progress(:attachments, entry, socket) do
    if entry.done? do
      {:noreply,
       Kotoba.Live.consume_uploads(socket, :attachments, @editor,
         storage: socket.assigns.storage,
         preview: socket.assigns.preview
       )}
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
  def delete(key), do: KotobaTest.EditorLive.report_delete(key)
end

defmodule KotobaTest.UnsafeStorage do
  @moduledoc "A `Kotoba.Storage` adapter that returns a URL that is not a safe link."
  @behaviour Kotoba.Storage

  @impl true
  def put(_key, _path, _meta), do: {:ok, "javascript:alert(1)"}

  @impl true
  def url(_key), do: "javascript:alert(1)"

  @impl true
  def delete(key), do: KotobaTest.EditorLive.report_delete(key)
end

defmodule KotobaTest.BrokenStorage do
  @moduledoc "A `Kotoba.Storage` adapter whose `put/3` breaks its contract."
  @behaviour Kotoba.Storage

  @impl true
  def put(_key, _path, _meta), do: {:ok, nil}

  @impl true
  def url(key), do: key

  @impl true
  def delete(key), do: KotobaTest.EditorLive.report_delete(key)
end
