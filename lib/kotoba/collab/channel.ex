defmodule Kotoba.Collab.Channel do
  @moduledoc """
  A Phoenix Channel with authenticated, read-only-aware collaboration.

      defmodule MyAppWeb.CollabChannel do
        use Kotoba.Collab.Channel, supervisor: MyApp.CollabSupervisor

        def authorize(socket, document_id, action) do
          if MyApp.can_access?(socket.assigns.current_user, document_id, action),
            do: :ok, else: {:error, :forbidden}
        end
      end

  `authorize/3` is required and runs on join and every transaction,
  awareness message and flush. `action` is `:read` or `:write`. Role claims
  also bound permissions: a read token cannot write. Configure the socket
  transport's `max_frame_size` as well as this module's message limit.
  """

  alias Kotoba.Collab.{DocServer, Supervisor}

  defmacro __using__(opts) do
    quote do
      use Phoenix.Channel
      @kotoba_collab_options unquote(opts)
      @impl Phoenix.Channel
      def join("kotoba:" <> id, params, socket),
        do: Kotoba.Collab.Channel.join(id, params, socket, __MODULE__, @kotoba_collab_options)

      @impl Phoenix.Channel
      def handle_in(event, payload, socket),
        do:
          Kotoba.Collab.Channel.handle_in(
            event,
            payload,
            socket,
            __MODULE__,
            @kotoba_collab_options
          )

      @impl Phoenix.Channel
      def handle_info(message, socket),
        do: Kotoba.Collab.Channel.handle_info(message, socket, __MODULE__)
    end
  end

  @doc false
  def join(id, %{"token" => token, "session" => session} = params, socket, module, opts)
      when is_binary(token) and is_binary(session) and byte_size(session) <= 160 do
    pending = Map.get(params, "pending", [])

    with {:ok, %{"document_id" => ^id, "role" => role, "user" => user} = claims} <-
           Kotoba.Collab.verify(socket.endpoint, token),
         true <-
           is_list(pending) and length(pending) <= 1_000 and Enum.all?(pending, &is_binary/1),
         socket = Phoenix.Socket.assign(socket, :kotoba_collab_user, user),
         :ok <- module.authorize(socket, id, :read),
         {:ok, server} <- Supervisor.open(Keyword.fetch!(opts, :supervisor), id),
         {:ok, payload} <-
           DocServer.subscribe(
             server,
             self(),
             %{"session" => session, "role" => role, "user" => user},
             pending
           ) do
      ref = Process.monitor(server)

      socket =
        Phoenix.Socket.assign(socket, :kotoba_collab, %{
          server: server,
          monitor: ref,
          id: id,
          claims: claims,
          session: session
        })

      {:ok, Map.put(payload, "role", role), socket}
    else
      {:error, :expired} -> {:error, %{"reason" => "expired"}}
      _ -> {:error, %{"reason" => "forbidden_or_unavailable"}}
    end
  end

  def join(_id, _params, _socket, _module, _opts), do: {:error, %{"reason" => "invalid_join"}}

  @doc false
  def handle_in(event, payload, socket, module, opts) do
    collab = socket.assigns.kotoba_collab
    action = if event == "transaction", do: :write, else: :read

    with true <-
           byte_size(JSON.encode!(payload)) <= Keyword.get(opts, :max_message_bytes, 1_000_000),
         :ok <- module.authorize(socket, collab.id, action),
         true <- action != :write or collab.claims["role"] == "write" do
      dispatch(event, payload, socket)
    else
      _ -> {:reply, {:error, %{"reason" => "forbidden_or_too_large"}}, socket}
    end
  end

  defp dispatch("transaction", payload, socket) do
    collab = socket.assigns.kotoba_collab
    reply(DocServer.commit(collab.server, payload, collab.claims["user"]["id"]), socket)
  end

  defp dispatch("flush", _payload, socket),
    do: reply(DocServer.snapshot(socket.assigns.kotoba_collab.server), socket)

  defp dispatch("awareness", %{"selection" => selection}, socket) do
    selection = if valid_selection?(selection), do: selection, else: nil
    DocServer.awareness(socket.assigns.kotoba_collab.server, self(), selection)
    {:reply, {:ok, %{}}, socket}
  end

  defp dispatch(_event, _payload, socket),
    do: {:reply, {:error, %{"reason" => "unknown_event"}}, socket}

  defp reply({:ok, payload}, socket), do: {:reply, {:ok, payload}, socket}

  defp reply({:error, reason}, socket),
    do: {:reply, {:error, %{"reason" => inspect(reason)}}, socket}

  @doc false
  def handle_info({:kotoba_collab, event, payload}, socket, module) do
    if module.authorize(socket, socket.assigns.kotoba_collab.id, :read) == :ok do
      Phoenix.Channel.push(socket, event, payload)
      {:noreply, socket}
    else
      {:stop, :normal, socket}
    end
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{kotoba_collab: %{monitor: ref}}} = socket,
        _module
      ),
      do: {:stop, :normal, socket}

  def handle_info(_message, socket, _module), do: {:noreply, socket}

  defp valid_selection?(nil), do: true

  defp valid_selection?(%{"anchor" => anchor, "focus" => focus}),
    do: valid_anchor?(anchor) and valid_anchor?(focus)

  defp valid_selection?(_), do: false

  defp valid_anchor?(%{"node" => node, "before" => before} = anchor),
    do:
      is_binary(node) and byte_size(node) <= 160 and
        (is_nil(before) or (is_binary(before) and byte_size(before) <= 160)) and
        (not Map.has_key?(anchor, "offset") or
           (is_integer(anchor["offset"]) and anchor["offset"] >= 0))

  defp valid_anchor?(_), do: false
end
