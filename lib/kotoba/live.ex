defmodule Kotoba.Live do
  @moduledoc """
  Helpers for a LiveView (or a LiveComponent) with a Kotoba editor.

  Each helper takes the socket and returns the socket, so that it fits in a
  `handle_event/3`, a `handle_info/2` or an upload progress callback. Every
  push carries the editor's `id` (the `id` of `Kotoba.Components.kotoba/1`),
  so that only that editor acts on it when a page has more than one
  editor.

  The editor pushes `kotoba:change` only when the component has `change`
  (see `Kotoba.Components.kotoba/1`); a form gets the document without it.

  ## Prompts

      def handle_event("kotoba:prompt", params, socket) do
        {:noreply, Kotoba.Live.handle_prompt(socket, params, prompts(socket))}
      end

      defp prompts(socket) do
        [people: fn query -> MyApp.People.search(socket.assigns.scope, query) end]
      end

  Give the same prompt list to the component (`prompts={prompts(@socket)}`,
  or build it once in `mount/3`). The component sends the triggers, the
  names, the options and the items of a local prompt to the browser; the
  search functions run here.

  ## Uploads

      def mount(_params, _session, socket) do
        {:ok,
         allow_upload(socket, :attachments,
           accept: ~w(.png .jpg .jpeg .gif .webp .pdf),
           max_file_size: 10_000_000,
           max_entries: 5,
           auto_upload: true,
           progress: &handle_progress/3
         )}
      end

      defp handle_progress(:attachments, entry, socket) do
        if entry.done? do
          {:noreply, Kotoba.Live.consume_uploads(socket, :attachments, "post-body")}
        else
          {:noreply, socket}
        end
      end

      # The form's phx-change handler, so that a file that fails validation
      # (too large, a type that is not accepted) loses its marker.
      def handle_event("validate", params, socket) do
        socket = Kotoba.Live.consume_uploads(socket, :attachments, "post-body")
        ...
      end

  and `<.kotoba field={@form[:body]} id="post-body" uploads={@uploads.attachments} />`
  in the form. The size limits and the accepted types are the ones of
  `Phoenix.LiveView.allow_upload/3`; the content type of each file is
  checked again on the server (see `Kotoba.Attachments`).
  """

  require Logger

  import Phoenix.LiveView, only: [push_event: 3, start_async: 3]

  alias Kotoba.{Content, Document, Prompts}
  alias Phoenix.LiveView.Socket

  @v 1

  # The private key of the entries that `consume_uploads/4` has consumed.

  @doc """
  Answers a `kotoba:prompt` event: runs the search of the prompt with the
  query, and pushes `kotoba:prompt_results` to the editor.

  `params` is the payload of the event (`%{"id", "prompt", "query"}`), and
  `prompts` the prompt list (see `Kotoba.Prompts`). The pushed payload is
  `%{id, prompt, query, items: [item]}`, with `error: true` when the search
  failed. The editor uses `query` to drop results that arrive after a
  newer query. A prompt name that is not in the list gives no items. A
  payload without a prompt and a query is ignored.

  The search of an `async: true` prompt runs in a task of the LiveView
  (`Phoenix.LiveView.start_async/3`), so the LiveView goes on while it
  runs. Its result comes to `handle_async/3`, which gives it to
  `handle_prompt_async/3`:

      def handle_async({:kotoba_prompt, _id, _prompt, _query} = name, result, socket) do
        {:noreply, Kotoba.Live.handle_prompt_async(socket, name, result)}
      end
  """
  @spec handle_prompt(Socket.t(), map(), Prompts.prompts()) :: Socket.t()
  def handle_prompt(socket, %{"prompt" => name, "query" => query} = params, prompts)
      when is_binary(name) and is_binary(query) do
    id = editor_id(params)

    case Prompts.find_spec(prompts, name) do
      nil ->
        push_prompt_results(socket, id, name, query, {:ok, []})

      %{async: true} = spec ->
        start_async(socket, {:kotoba_prompt, id, name, query}, fn ->
          Prompts.search(spec, query)
        end)

      spec ->
        push_prompt_results(socket, id, name, query, Prompts.search(spec, query, socket))
    end
  end

  def handle_prompt(%Socket{} = socket, _params, _prompts), do: socket

  @doc """
  Pushes the result of the search of an `async: true` prompt (see
  `handle_prompt/3`) to the editor. `name` and `result` are the arguments
  of `handle_async/3`. A search that exits (a crash or a timeout of the
  task) gives `error: true`, as a search that fails.
  """
  @spec handle_prompt_async(Socket.t(), term(), {:ok, term()} | {:exit, term()}) :: Socket.t()
  def handle_prompt_async(socket, {:kotoba_prompt, id, name, query}, result)
      when is_binary(name) and is_binary(query) do
    result =
      case result do
        {:ok, {:ok, items}} when is_list(items) ->
          {:ok, items}

        {:ok, _error} ->
          :error

        {:exit, reason} ->
          Logger.warning("the Kotoba prompt #{inspect(name)} exited: #{inspect(reason)}")
          :error
      end

    push_prompt_results(socket, id, name, query, result)
  end

  def handle_prompt_async(%Socket{} = socket, _name, _result), do: socket

  defp push_prompt_results(socket, id, name, query, result) do
    payload =
      case result do
        {:ok, items} -> %{prompt: name, query: query, items: items}
        :error -> %{prompt: name, query: query, items: [], error: true}
      end

    push_event(socket, "kotoba:prompt_results", payload(id, payload))
  end

  @doc """
  Replaces the document of the editor `id` (`set_content`).

  `content` is a `Kotoba.Content`, a `Kotoba.Document`, or anything that
  `Kotoba.Content.cast/1` accepts. The editor clears its undo history and
  does not push `kotoba:change` for it.

  Raises `ArgumentError` when `content` is not a valid document.
  """
  @spec push_content(Socket.t(), String.t(), Content.t() | Document.t() | map() | String.t()) ::
          Socket.t()
  def push_content(socket, id, content) when is_binary(id) do
    push_event(socket, "set_content", payload(id, %{doc: envelope!(content)}))
  end

  defp envelope!(%Document{} = doc), do: Document.to_json(doc)

  defp envelope!(content) do
    case Content.cast(content) do
      {:ok, %Content{doc: doc}} -> doc
      :error -> raise ArgumentError, "not a valid Kotoba document: #{inspect(content)}"
    end
  end

  @doc """
  Inserts a node in the editor `id` (`insert_node`), at the selection.

  `node` is a node struct (a module that uses `Kotoba.Node`), which is sent
  in its JSON form (camelCase keys, as in Lexical), or a node JSON map. The
  editor refuses a node of a type that it does not know.

  ## Options

    * `:ref` - the ref of a LiveView upload entry. The node takes the place
      of that upload's marker. Without it, the node takes the place of the
      oldest marker, if any.

  Raises `ArgumentError` when a node struct is not valid.
  """
  @spec insert_node(Socket.t(), String.t(), Kotoba.Node.t() | map(), keyword()) :: Socket.t()
  def insert_node(socket, id, node, opts \\ []) when is_binary(id) do
    extra = if ref = opts[:ref], do: %{node: json!(node), ref: ref}, else: %{node: json!(node)}
    push_event(socket, "insert_node", payload(id, extra))
  end

  @doc """
  Inserts an embed (`Kotoba.Nodes.Embed`) in the editor `id`, at the
  person's selection, and closes the editor's embeds picker
  (`Kotoba.Components.kotoba_embeds/1`).

      def handle_event("insert_diagram", %{"id" => id}, socket) do
        diagram = Diagrams.get!(id)
        {:noreply, Kotoba.Live.insert_embed(socket, "post-body", "canvas", diagram.id, title: diagram.title)}
      end

  ## Options

    * `:title` - the embed's title, for the text and the Markdown of the
      document.
  """
  @spec insert_embed(Socket.t(), String.t(), String.t(), String.t(), keyword()) :: Socket.t()
  def insert_embed(socket, id, kind, ref, opts \\ []) when is_binary(id) do
    Phoenix.LiveView.send_update(Kotoba.Embeds, id: id <> "-embeds", picker: false)

    socket
    |> insert_node(id, %Kotoba.Nodes.Embed{
      kind: to_string(kind),
      ref: to_string(ref),
      title: opts[:title] || ""
    })
    |> focus(id)
  end

  defp json!(%module{} = node) do
    unless Kotoba.Node.node_module?(module) do
      raise ArgumentError, "not a Kotoba node: #{inspect(node)}"
    end

    case module.validate(node) do
      :ok -> Kotoba.Node.encode(node)
      {:error, errors} -> raise ArgumentError, "invalid #{module.type()} node: #{inspect(errors)}"
    end
  end

  defp json!(%{"type" => type} = json) when is_binary(type), do: json
  defp json!(other), do: raise(ArgumentError, "not a Kotoba node: #{inspect(other)}")

  @doc "Makes the editor `id` read-only, or editable again (`set_readonly`)."
  @spec set_readonly(Socket.t(), String.t(), boolean()) :: Socket.t()
  def set_readonly(socket, id, readonly) when is_binary(id) and is_boolean(readonly) do
    push_event(socket, "set_readonly", payload(id, %{readonly: readonly}))
  end

  @doc "Moves the focus to the editor `id` (`focus`)."
  @spec focus(Socket.t(), String.t()) :: Socket.t()
  def focus(socket, id) when is_binary(id), do: push_event(socket, "focus", payload(id, %{}))

  @stream_targets [:selection, :caret, :after, :end]
  @stream_formats [:markdown, :text]

  @doc """
  Returns a new ref for a stream that the server starts by itself. A
  stream that answers a `kotoba:assist` event takes the event's `"ref"`.
  """
  @spec stream_ref() :: String.t()
  def stream_ref, do: "k" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

  @doc """
  Starts a suggestion in the editor `id`: text that the server streams
  with `stream_chunk/4` and ends with `stream_end/3`. See the
  [Suggestions](suggestions.md) guide.

  The text is not in the document while it streams: the editor shows it in
  a panel, or in the text where it goes (`display: :inline`), and the
  person accepts it (it goes into the document, as one undo step) or
  rejects it. A new stream in the same editor replaces the open
  suggestion.

  `ref` is the ref of the `kotoba:assist` event that asked for it, or a new
  one from `stream_ref/0`.

  ## Options

    * `:at` - where the text goes: `:selection` (in place of the
      selection, the default), `:caret`, `:after` (after the block of the
      selection) or `:end` (at the end of the document). The selection is
      the one of the `kotoba:assist` request, or the editor's selection
      when the stream starts.
    * `:format` - `:markdown` (the default) or `:text`. Markdown has only
      the formats and blocks of the editor's features.
    * `:label` - the name of the suggestion, for example `"Rewrite"`.
    * `:block` - the block the text goes after (`at: :after`) or at the end
      of (`:caret`, `:selection`), in place of the selection: its number
      (1 for the first top-level block), or its id in a shared document.
      The `kotoba:assist` event's `"place"` has both (`%{"block" => 3,
      "id" => ...}`). A block that is not there gives the end of the
      document. For a stream that resumes, see `stream_resume/5`.
    * `:selection` - in a shared editor, the selection the text replaces
      (`at: :selection`), as a place of the document (`Kotoba.Issho.Place`):
      the `kotoba:assist` event's `"place"` has it (`"selection"`), and so
      does a person's place in the room. It holds on the same words
      however the text around it changed, from any tab, after a reload; a
      selection whose words are gone gives the end of the document.
    * `:display` - `:panel` (the default): the text streams in a panel under
      the editable area; `:inline`: it streams in the text, where it goes
      (after the caret, after the selection it replaces, or in a block
      below), marked as a suggestion, with its status and buttons under
      it. Inline or not, it is not in the saved document, nor seen by the
      others in a shared editor, until the person accepts it.
  """
  @spec stream_start(Socket.t(), String.t(), String.t(), keyword()) :: Socket.t()
  def stream_start(socket, id, ref, opts \\ []) when is_binary(id) and is_binary(ref) do
    push_event(socket, "kotoba:stream", payload(id, start_fields(ref, opts)))
  end

  @doc """
  Starts a suggestion in the middle of its stream: with `text`, the text so
  far, shown at once. `stream_chunk/4` and `stream_end/3` go on from there.
  It takes the options of `stream_start/4`.

  It is for a stream that goes on while the person is on another page:
  the app's process keeps the text and broadcasts each chunk, and a
  LiveView that mounts resumes it and subscribes. Give it `:block` (from
  the request's `"place"`), as the selection of the request is gone with
  the page. The Suggestions guide has the recipe, "A stream that outlives
  the page".

      Kotoba.Live.stream_resume(socket, "post-body", ref, text, at: :after, block: place["id"] || place["block"])
  """
  @spec stream_resume(Socket.t(), String.t(), String.t(), String.t(), keyword()) :: Socket.t()
  def stream_resume(socket, id, ref, text, opts \\ [])
      when is_binary(id) and is_binary(ref) and is_binary(text) do
    push_event(
      socket,
      "kotoba:stream",
      payload(id, Map.put(start_fields(ref, opts), :text, text))
    )
  end

  defp start_fields(ref, opts) do
    at = one_of!(opts, :at, :selection, @stream_targets, "one of #{inspect(@stream_targets)}")

    format =
      one_of!(opts, :format, :markdown, @stream_formats, "one of #{inspect(@stream_formats)}")

    display = one_of!(opts, :display, :panel, [:panel, :inline], ":panel or :inline")

    %{ref: ref, op: "start", at: Atom.to_string(at), format: Atom.to_string(format)}
    |> put_some(:display, display == :inline && "inline")
    |> put_some(:label, opts[:label] && to_string(opts[:label]))
    |> put_some(:block, block!(opts))
    |> put_some(:selection, selection!(opts))
  end

  defp selection!(opts) do
    case Keyword.get(opts, :selection) do
      nil ->
        nil

      %{"anchor" => %{"node" => anchor}, "focus" => %{"node" => focus}} = selection
      when is_binary(anchor) and is_binary(focus) ->
        selection

      other ->
        raise ArgumentError,
              "stream :selection must be a Kotoba place (%{\"anchor\" => ..., \"focus\" => ...}), got: #{inspect(other)}"
    end
  end

  defp one_of!(opts, key, default, values, expected) do
    value = Keyword.get(opts, key, default)

    if value in values,
      do: value,
      else:
        raise(ArgumentError, "stream #{inspect(key)} must be #{expected}, got: #{inspect(value)}")
  end

  defp block!(opts) do
    case Keyword.get(opts, :block) do
      nil ->
        nil

      block when (is_integer(block) and block >= 1) or (is_binary(block) and block != "") ->
        block

      block ->
        raise ArgumentError,
              "stream :block must be a block number (1 or more) or a block id, got: #{inspect(block)}"
    end
  end

  defp put_some(fields, _key, value) when value in [nil, false], do: fields
  defp put_some(fields, key, value), do: Map.put(fields, key, value)

  @doc """
  Adds text to the suggestion `ref` of the editor `id`. The chunks can cut
  the text anywhere, Markdown syntax included: the editor reads the whole
  text again at each chunk.
  """
  @spec stream_chunk(Socket.t(), String.t(), String.t(), String.t()) :: Socket.t()
  def stream_chunk(socket, id, ref, text)
      when is_binary(id) and is_binary(ref) and is_binary(text) do
    push_event(socket, "kotoba:stream", payload(id, %{ref: ref, op: "chunk", text: text}))
  end

  @doc """
  Ends the suggestion `ref` of the editor `id`: the person can accept or
  reject it.
  """
  @spec stream_end(Socket.t(), String.t(), String.t()) :: Socket.t()
  def stream_end(socket, id, ref) when is_binary(id) and is_binary(ref) do
    push_event(socket, "kotoba:stream", payload(id, %{ref: ref, op: "end"}))
  end

  @doc """
  Cancels the suggestion `ref` of the editor `id`, for example when the
  model failed: the editor closes it, and the document stays as it was.
  """
  @spec stream_cancel(Socket.t(), String.t(), String.t()) :: Socket.t()
  def stream_cancel(socket, id, ref) when is_binary(id) and is_binary(ref) do
    push_event(socket, "kotoba:stream", payload(id, %{ref: ref, op: "cancel"}))
  end

  @doc """
  Removes the upload marker of the LiveView upload entry `ref` from the
  editor `id` (`remove_marker`), for an upload that failed.
  """
  @spec remove_marker(Socket.t(), String.t(), String.t()) :: Socket.t()
  def remove_marker(socket, id, ref) when is_binary(id) and is_binary(ref) do
    push_event(socket, "remove_marker", payload(id, %{ref: ref}))
  end

  if Code.ensure_loaded?(Storehouse) do
    alias Kotoba.{Attachments, Storage}
    alias Phoenix.LiveView
    alias Phoenix.LiveView.{UploadConfig, UploadEntry}

    @consumed :kotoba_consumed_uploads

    @doc """
    Stores the finished uploads of `upload_name` and puts an attachment node
    for each in the editor `editor_id`. It needs
    [Storehouse](https://hexdocs.pm/storehouse) in the app's deps
    (`{:storehouse, "~> 0.2"}`).

    For each entry:

      * An entry that is done is consumed (`Phoenix.LiveView.consume_uploaded_entry/3`).
        Its file is checked (`Kotoba.Attachments.describe/2`), stored under a
        new key (`Storehouse.key/2`, with the extension of the checked
        type) through the storage adapter, and an attachment node with the
        URL from the adapter is pushed with `insert_node/4` (with the entry's
        `ref`, so it takes the place of that file's marker). When the check
        fails, or the adapter gives an error or a result that does not make
        a valid attachment (a URL that is not a safe link, say), a warning is
        logged and the marker is removed with `remove_marker/3`.
      * An entry with an error (too large, a type that is not accepted) is
        cancelled, and its marker is removed. Read `upload_errors/2` before
        this call to show the error.
      * An entry still in progress is left alone.

    An entry is consumed once: a call before LiveView has dropped an entry
    that an earlier call consumed leaves it alone. So the function can run
    in the progress callback and in the form's change handler, with files
    that finish at different times.

    ## Options

      * `:storage` - the store (a `Storehouse.Adapter`). The default is
        `Kotoba.Storage.adapter/0`.
      * `:key` - a function of the upload entry and the checked content
        type that returns a storage key. The default is
        `&Storehouse.key(&1.client_name, &2)`.
      * `:preview` - a function of the stored attachment
        (`Kotoba.Nodes.Attachment`) and the path of the uploaded file that
        returns the URL of a preview image, or `nil`: the first page of a
        PDF, the poster frame of a video. It runs after the file is stored,
        while its temporary file is still there; the app renders and stores
        the image. A result that is not a safe URL, or an exception, gives no
        preview and logs a warning. See the Uploads guide.
    """
    @spec consume_uploads(Socket.t(), atom() | String.t(), String.t(), keyword()) :: Socket.t()
    def consume_uploads(%Socket{} = socket, upload_name, editor_id, opts \\ [])
        when is_binary(editor_id) do
      storage = Keyword.get_lazy(opts, :storage, &Storage.adapter/0)
      key_fun = Keyword.get(opts, :key, &Storehouse.key(&1.client_name, &2))
      preview_fun = Keyword.get(opts, :preview)
      entries = entries(socket, upload_name)

      socket = Enum.reduce(entries.invalid, socket, &drop_invalid(&2, upload_name, editor_id, &1))

      # LiveView drops a consumed entry only when its upload channel has
      # closed, a message later. A second call before that (the next file
      # done, a form change) must not consume it again: its channel is gone,
      # and the call would crash the LiveView.
      key = {@consumed, upload_name}
      consumed = Map.get(socket.private, key, MapSet.new())
      done = Enum.reject(entries.done, &MapSet.member?(consumed, &1.ref))

      kept =
        entries.all
        |> MapSet.new(& &1.ref)
        |> MapSet.intersection(consumed)
        |> MapSet.union(MapSet.new(done, & &1.ref))

      socket = %{socket | private: Map.put(socket.private, key, kept)}

      Enum.reduce(done, socket, fn entry, socket ->
        result =
          LiveView.consume_uploaded_entry(
            socket,
            entry,
            &store(&1, entry, storage, key_fun, preview_fun)
          )

        case result do
          {:ok, attachment} ->
            insert_node(socket, editor_id, attachment, ref: entry.ref)

          {:error, reason} ->
            Logger.warning(
              "Kotoba: the upload #{inspect(entry.client_name)} was not stored: #{inspect(reason)}"
            )

            remove_marker(socket, editor_id, entry.ref)
        end
      end)
    end

    defp entries(socket, upload_name) do
      case socket.assigns[:uploads] do
        %{^upload_name => %UploadConfig{} = conf} ->
          %{
            all: conf.entries,
            invalid: Enum.reject(conf.entries, & &1.valid?),
            done: Enum.filter(conf.entries, &(&1.valid? and &1.done?))
          }

        _other ->
          raise ArgumentError, "no upload allowed for #{inspect(upload_name)}"
      end
    end

    defp drop_invalid(socket, upload_name, editor_id, %UploadEntry{ref: ref}) do
      socket
      |> LiveView.cancel_upload(upload_name, ref)
      |> remove_marker(editor_id, ref)
    end

    # The consume callback always returns {:ok, _}: a file that could not be
    # stored is still consumed (its temporary file is removed), and the
    # result says what happened.
    defp store(%{path: path}, entry, storage, key_fun, preview_fun) do
      {:ok,
       Attachments.store(path,
         name: entry.client_name,
         content_type: entry.client_type,
         storage: storage,
         key: fn _name, content_type -> key_fun.(entry, content_type) end,
         preview: preview_fun
       )}
    end
  else
    @doc false
    # Uploads with no Storehouse in the app's deps: the developer learns
    # what is missing, not that a function is undefined.
    def consume_uploads(_socket, _upload_name, _editor_id, _opts \\ []),
      do: missing_storehouse!()
  end

  @doc false
  @spec missing_storehouse!() :: no_return()
  def missing_storehouse! do
    raise ArgumentError, """
    Kotoba's uploads keep their files with Storehouse, which is not in the \
    app's deps. Add it to mix.exs, and run mix deps.get:

        {:storehouse, "~> 0.2"}

    An editor without uploads (no `uploads` on <.kotoba>) does not need it.
    """
  end

  defp editor_id(%{"id" => id}) when is_binary(id) and id != "", do: id
  defp editor_id(_params), do: nil

  defp payload(nil, map), do: Map.put(map, :v, @v)
  defp payload(id, map), do: map |> Map.put(:v, @v) |> Map.put(:id, id)
end
