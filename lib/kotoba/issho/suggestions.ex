if Code.ensure_loaded?(Issho.Streams) do
  defmodule Kotoba.Issho.Suggestions do
    @moduledoc false
    # Issho's streams (Issho.Streams) as the suggestions of a LiveView's
    # shared editors: see Kotoba.Issho.suggestions/4.

    import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, put_private: 3]

    alias Kotoba.Live

    @key :kotoba_issho_suggestions

    def attach(socket, user, editors, opts) do
      editors = Map.new(editors, fn {id, issho} -> {to_string(id), Keyword.new(issho)} end)

      state = %{
        # document id => editor id, and room => instance
        docs: Map.new(editors, fn {id, issho} -> {Keyword.fetch!(issho, :document), id} end),
        rooms:
          editors
          |> Map.values()
          |> Map.new(
            &{Issho.Policy.room(Keyword.fetch!(&1, :document)), Keyword.fetch!(&1, :instance)}
          ),
        display: Keyword.get(opts, :display, :panel),
        kinds: opts[:kinds] && Enum.map(List.wrap(opts[:kinds]), &to_string/1),
        # The app's handle_info gets the messages of the streams that are not suggestions.
        pass: Keyword.get(opts, :pass, false),
        # stream id => %{editor, room}; editor id => the stream it shows, and the ones that wait
        streams: %{},
        shown: %{},
        waiting: %{}
      }

      socket =
        socket
        |> put_private(@key, state)
        |> attach_hook(@key, :handle_info, &handle_info/2)
        |> attach_hook(@key, :handle_event, &handle_event/3)

      if connected?(socket), do: watch(socket, user), else: socket
    end

    # Joins each room, and offers the streams there are.
    defp watch(socket, user) do
      Enum.reduce(state(socket).rooms, socket, fn {room, instance}, socket ->
        with {:ok, _session} <- Issho.Live.join(instance, user, room),
             {:ok, streams} <- Issho.Live.streams(room) do
          Enum.reduce(streams, socket, &offer(&2, &1))
        else
          _error -> socket
        end
      end)
    end

    defp state(socket), do: socket.private[@key]
    defp put_state(socket, state), do: put_private(socket, @key, state)

    # A stream that is a suggestion of one of the editors: for this person,
    # with a place in its document, of a kind it shows, and not ended.
    defp offer(socket, %Issho.Stream{} = stream) do
      state = state(socket)

      with %{"doc" => doc} <- stream.place,
           {:ok, editor} <- Map.fetch(state.docs, doc),
           true <- state.kinds == nil or stream.kind in state.kinds,
           true <- stream.state in [:writing, :finished] do
        state = put_in(state.streams[stream.id], %{editor: editor, room: stream.room})

        if Map.has_key?(state.shown, editor) do
          put_state(socket, wait(state, editor, stream.id))
        else
          socket |> put_state(put_in(state.shown[editor], stream.id)) |> show(editor, stream)
        end
      else
        _not_a_suggestion -> socket
      end
    end

    # An editor shows one suggestion at a time: the others wait their turn.
    defp wait(state, editor, id),
      do: %{state | waiting: Map.update(state.waiting, editor, [id], &(&1 ++ [id]))}

    defp show(socket, editor, stream) do
      socket =
        Live.stream_resume(
          socket,
          editor,
          stream.id,
          stream.content,
          [label: label(stream), display: state(socket).display] ++ target(stream.place["at"])
        )

      if stream.state == :finished, do: Live.stream_end(socket, editor, stream.id), else: socket
    end

    # Where it goes: in place of a selection (a Kotoba place whose ends
    # differ), else after the block of its place.
    defp target(%{"anchor" => anchor, "focus" => focus} = selection) when anchor != focus,
      do: [at: :selection, selection: selection]

    defp target(at), do: [at: :after, block: block(at)]

    # The block of a place: a node id (`%{"node" => id}`), or a Kotoba
    # selection (`Kotoba.Issho.Place`), whose focus is in the block.
    defp block(%{"node" => id}) when is_binary(id), do: id
    defp block(%{"focus" => %{"node" => id}}) when is_binary(id), do: id
    defp block(_at), do: nil

    defp label(%Issho.Stream{meta: %{"label" => label}}) when is_binary(label), do: label
    defp label(%Issho.Stream{kind: kind}) when is_binary(kind), do: String.capitalize(kind)
    defp label(_stream), do: "Suggestion"

    # The stream's messages.
    defp handle_info({Issho, :stream, _id, {:started, stream}}, socket),
      do: {:cont, offer(socket, stream)}

    defp handle_info({Issho, :stream, id, message}, socket) do
      state = state(socket)

      case state.streams do
        %{^id => %{done: true}} when message == :gone ->
          {:halt, put_state(socket, %{state | streams: Map.delete(state.streams, id)})}

        # Its last messages, after the person answered it.
        %{^id => %{done: true}} ->
          {:halt, socket}

        %{^id => %{editor: editor}} ->
          {:halt, on_stream(socket, id, editor, message)}

        _other ->
          if state.pass, do: {:cont, socket}, else: {:halt, socket}
      end
    end

    defp handle_info(_message, socket), do: {:cont, socket}

    defp on_stream(socket, id, editor, message) do
      shown? = state(socket).shown[editor] == id

      case message do
        {:chunk, text} when shown? ->
          Live.stream_chunk(socket, editor, id, text)

        :finished when shown? ->
          Live.stream_end(socket, editor, id)

        # Failed, closed (accepted in another tab), or gone: it goes, and the next shows.
        ended when ended == :gone or elem(ended, 0) in [:failed, :closed] ->
          drop(socket, id, editor, shown?)

        _waiting ->
          socket
      end
    end

    defp drop(socket, id, editor, shown?) do
      socket = if shown?, do: Live.stream_cancel(socket, editor, id), else: socket
      forget(socket, id, editor)
    end

    # Forgets a stream (its last messages are dropped), and shows the next
    # one of its editor.
    defp forget(socket, id, editor) do
      state = state(socket)

      state = %{
        state
        | streams: Map.update(state.streams, id, %{done: true}, &Map.put(&1, :done, true)),
          waiting: Map.update(state.waiting, editor, [], &List.delete(&1, id))
      }

      if state.shown[editor] == id do
        state = %{state | shown: Map.delete(state.shown, editor)}
        next(put_state(socket, state), editor)
      else
        put_state(socket, state)
      end
    end

    defp next(socket, editor) do
      state = state(socket)

      case Map.get(state.waiting, editor, []) do
        [] ->
          socket

        [id | rest] ->
          state = %{state | waiting: Map.put(state.waiting, editor, rest)}
          %{room: room} = state.streams[id]

          case Issho.Streams.get(state.rooms[room], id) do
            {:ok, %Issho.Stream{state: live} = stream} when live in [:writing, :finished] ->
              socket |> put_state(put_in(state.shown[editor], id)) |> show(editor, stream)

            _gone ->
              forget(put_state(socket, state), id, editor)
          end
      end
    end

    # The person's answer to a suggestion: Accept, Reject and Stop close
    # the stream; an editor that went away does not.
    defp handle_event("kotoba:suggestion", %{"ref" => id} = params, socket) do
      case state(socket).streams do
        %{^id => %{done: true}} ->
          {:halt, socket}

        %{^id => %{editor: editor, room: room}} ->
          {:halt, answer(socket, id, editor, room, params)}

        _other ->
          {:cont, socket}
      end
    end

    defp handle_event(_event, _params, socket), do: {:cont, socket}

    defp answer(socket, _id, _editor, _room, %{"gone" => true}), do: socket

    defp answer(socket, id, editor, room, %{"action" => action}) do
      outcome =
        case action do
          "accept" -> :accepted
          "reject" -> :rejected
          _stop -> :stopped
        end

      _ = Issho.Live.close_stream(room, id, outcome)
      forget(socket, id, editor)
    end
  end
end
