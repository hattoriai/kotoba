# Suggestions

A suggestion is text that the server streams into the editor: the answer
of a language model to "Rewrite this", a summary, the next paragraph. The
text shows as it comes, in a panel under the editable area, and goes into
the document only when the person accepts it.

* The text is not in the document while it streams. A Markdown format cut
  in two by a chunk (`**bo` then `ld**`) is never half a format in the
  document.
* Accept inserts it as one undo step. Reject leaves the document and the
  selection as they were.
* The person can go on editing meanwhile: the suggestion goes where the
  selection was when it was asked for.
* A suggestion has only the formats and blocks of the editor's features.

The development server of this repository (`mix dev`) has an Assist menu
answered by a fake model, with no API key.

## Stream from the server

Four functions of `Kotoba.Live` push a stream to the editor with the id
`"post-body"`:

```elixir
ref = Kotoba.Live.stream_ref()

socket
|> Kotoba.Live.stream_start("post-body", ref, at: :end, label: "Summary")
|> Kotoba.Live.stream_chunk("post-body", ref, "## Sum")
|> Kotoba.Live.stream_chunk("post-body", ref, "mary\n\nThe **main** point.")
|> Kotoba.Live.stream_end("post-body", ref)
```

In a real app the chunks come later, from a process (see
[A language model](#a-language-model) below). The functions:

* `stream_start/4` opens the panel. A new stream in the same editor
  replaces the open suggestion.
* `stream_chunk/4` adds text. The editor renders the whole text again at
  each chunk, so a chunk can end anywhere.
* `stream_end/3` ends it: the person can now accept or reject it.
* `stream_cancel/3` closes the panel with nothing inserted. Use it when
  the work fails: the live region says "The suggestion was cancelled".

`ref` names the stream. A stream that answers the Assist menu takes the
ref of its request; one that the server starts by itself takes a new ref
from `Kotoba.Live.stream_ref/0`. The editor ignores chunks of a ref that
is not the open suggestion.

### Where the text goes

`:at` chooses the place:

| `:at` | The text goes |
| --- | --- |
| `:selection` (default) | in place of the selection |
| `:caret` | at the caret, or at the start of the selection |
| `:after` | in new blocks after the block of the selection |
| `:end` | at the end of the document |

The selection is the one of the request (the Assist menu), or the
editor's selection when the stream starts. When that text is no longer in
the document (the person deleted it, or the server loaded a new
document), the suggestion goes at the end.

### Markdown or plain text

`:format` is `:markdown` (the default) or `:text`.

Markdown is read with the editor's own Markdown shortcuts: `**bold**`,
`_italic_`, `` `code` ``, `[links](https://example.com)`, `## headings`,
`- lists`, `1. lists`, `- [ ] check lists`, `> quotes`, code blocks and
`---`. Markdown of a feature that the editor does not have stays text: in
an editor without `headings`, `## Title` is a paragraph with `## Title`
in it. A suggestion of a single paragraph at `:selection` or `:caret`
goes into the paragraph, in the line; one with blocks adds blocks.

Plain text has no formats: a blank line starts a new paragraph, and a
single newline is a line break.

The stored document is checked as always: `Kotoba.Content` sanitizes it,
and `Kotoba.Content.validate_features/3` checks its features (see
[Forms and changesets](forms.md)).

## The Assist menu

Give the editor a list of actions with `assist`:

```heex
<.kotoba
  field={@form[:body]}
  id="post-body"
  assist={[rewrite: "Rewrite", summarize: "Summarize", continue: "Continue writing"]}
/>
```

The toolbar gets an Assist button, which opens a menu of the actions. An
action is `{id, label}` (the id an atom or a string) or `%{id: id,
label: label}`. `assist={true}` has no menu, only the events (for an
extension's buttons, below); with no `assist`, the editor sends no assist
events.

An action pushes `kotoba:assist` with a new `ref`, the action's `id` and
the selected text (`""` with no selection). Answer with a stream of that
ref:

```elixir
def handle_event("kotoba:assist", %{"ref" => ref, "action" => action, "text" => text}, socket) do
  socket = Kotoba.Live.stream_start(socket, "post-body", ref, at: at(action), label: label(action))
  {:noreply, start_writer(socket, ref, action, text)}
end

defp at("rewrite"), do: :selection
defp at(_action), do: :after
```

The editor then pushes `kotoba:suggestion` with the `ref` and an
`action`:

* `"accept"`: the person accepted it;
* `"reject"`: the person rejected it, or the server loaded a new document
  over it, or started another stream;
* `"stop"`: the person stopped it while it streamed, or the editor did (a
  new document, another stream, 30 seconds with no chunk, or the editor
  was removed from the page).

Stop the work on `"stop"` and `"reject"`: the editor ignores the chunks
that come after. What had come stays in the panel, and the person can
still accept it.

Both events have the editor's `id`, and go to the editor's `phx-target`
when it has one, as the other events do (see
[Forms and changesets](forms.md)).

### From an extension

An extension can ask for a suggestion from its own button or shortcut
with `context.assist(action, detail)`. It pushes `kotoba:assist` as the
menu does, with the keys of `detail` too, and returns the ref (or `null`
when the editor has no `assist`):

```js
register(editor, context) {
  return editor.registerCommand(TRANSLATE_COMMAND, (language) => {
    context.assist("translate", { language });
    return true;
  }, COMMAND_PRIORITY_EDITOR);
}
```

See the [Extensions](extensions.md) guide.

## A language model

This LiveView streams the answer of Claude, from the Anthropic Messages
API, with [Req](https://hexdocs.pm/req). The request runs in a task, which
sends each text chunk to the LiveView. The LiveView keeps the task of each
ref, to stop it when the person stops or rejects the suggestion.

Add a task supervisor to your application's children:

```elixir
{Task.Supervisor, name: MyApp.TaskSupervisor}
```

The writer:

```elixir
defmodule MyApp.Writer do
  @moduledoc "Streams Claude's answer to `lv` as `{:writer, ref, message}`."

  @url "https://api.anthropic.com/v1/messages"

  @system """
  You edit a document with its author. Answer with the new text only, in
  Markdown, with no preface and no comment.
  """

  def start(lv, ref, prompt) do
    Task.Supervisor.start_child(MyApp.TaskSupervisor, fn -> stream(lv, ref, prompt) end)
  end

  defp stream(lv, ref, prompt) do
    body = %{
      model: "claude-opus-5-5",
      max_tokens: 16_000,
      stream: true,
      system: @system,
      messages: [%{role: "user", content: prompt}]
    }

    result =
      Req.post(@url,
        json: body,
        headers: [
          {"x-api-key", System.fetch_env!("ANTHROPIC_API_KEY")},
          {"anthropic-version", "2023-06-01"}
        ],
        receive_timeout: 120_000,
        # A retry would send the chunks again.
        retry: false,
        into: fn {:data, data}, {req, resp} ->
          # Server-sent events: an event ends with a blank line, and a
          # piece of data can end in the middle of one.
          [rest | events] =
            (Req.Response.get_private(resp, :sse, "") <> data)
            |> String.split("\n\n")
            |> Enum.reverse()

          events |> Enum.reverse() |> Enum.each(&event(&1, lv, ref))
          {:cont, {req, Req.Response.put_private(resp, :sse, rest)}}
        end
      )

    case result do
      {:ok, %{status: 200}} -> send(lv, {:writer, ref, :done})
      _error -> send(lv, {:writer, ref, :error})
    end
  end

  defp event(event, lv, ref) do
    with "data: " <> json <- event |> String.split("\n") |> List.last(),
         {:ok, data} <- JSON.decode(json) do
      case data do
        %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => text}} ->
          send(lv, {:writer, ref, {:chunk, text}})

        # The model declined to answer, or the API failed in the stream.
        %{"type" => "message_delta", "delta" => %{"stop_reason" => "refusal"}} ->
          send(lv, {:writer, ref, :error})

        %{"type" => "error"} ->
          send(lv, {:writer, ref, :error})

        _other ->
          :ok
      end
    end
  end
end
```

The LiveView:

```elixir
@editor "post-body"

def mount(_params, _session, socket) do
  {:ok, assign(socket, writers: %{})}
end

def handle_event("kotoba:assist", %{"ref" => ref, "action" => action, "text" => text}, socket) do
  {:ok, pid} = MyApp.Writer.start(self(), ref, prompt(action, text))

  socket =
    socket
    |> Kotoba.Live.stream_start(@editor, ref, at: at(action), label: label(action))
    |> update(:writers, &Map.put(&1, ref, pid))

  {:noreply, socket}
end

def handle_event("kotoba:suggestion", %{"ref" => ref}, socket) do
  {pid, writers} = Map.pop(socket.assigns.writers, ref)
  if pid, do: Task.Supervisor.terminate_child(MyApp.TaskSupervisor, pid)
  {:noreply, assign(socket, writers: writers)}
end

def handle_info({:writer, ref, message}, socket) do
  if Map.has_key?(socket.assigns.writers, ref) do
    {:noreply, writer(socket, ref, message)}
  else
    # A stopped or finished writer.
    {:noreply, socket}
  end
end

defp writer(socket, ref, {:chunk, text}), do: Kotoba.Live.stream_chunk(socket, @editor, ref, text)

defp writer(socket, ref, :done) do
  socket |> Kotoba.Live.stream_end(@editor, ref) |> update(:writers, &Map.delete(&1, ref))
end

defp writer(socket, ref, :error) do
  socket |> Kotoba.Live.stream_cancel(@editor, ref) |> update(:writers, &Map.delete(&1, ref))
end

defp prompt("rewrite", text), do: "Rewrite this text to make it clearer:\n\n#{text}"
defp prompt("summarize", text), do: "Summarize this text in one paragraph:\n\n#{text}"
defp prompt("continue", text), do: "Write the next paragraph after this text:\n\n#{text}"

defp at("rewrite"), do: :selection
defp at(_action), do: :after

defp label("rewrite"), do: "Rewrite"
defp label("summarize"), do: "Summary"
defp label("continue"), do: "Continue writing"
```

Some things to know:

* A task under `Task.Supervisor` is not linked to the LiveView: when the
  person leaves the page, it runs to its end, and its messages go
  nowhere. To stop it with the LiveView, stop the tasks of `writers` in
  `terminate/2`, or run it with `Task.Supervisor.async_nolink/3` and
  handle its reply and `:DOWN` message.
* A long answer can take a minute. `receive_timeout` is the longest wait
  for one piece of data, not for the whole answer.
* The selected text goes to the model. Tell your users so, and do not
  send what they would not want sent.
* The model can write any Markdown. The editor keeps only its features,
  and the server checks the saved document, so the answer cannot add
  scripts, styles or links with other schemes (see [Security](security.md)).
* A chunk of text is a push to the browser. With a model that sends many
  small chunks, you can join them for 50 ms before a push; the editor
  renders at most once a frame anyway.

## The keyboard and assistive technology

* The Assist button has `aria-haspopup="menu"` and `aria-expanded`. Enter,
  Space or a click opens the menu (`role="menu"`, named "Assist"), with
  the focus on its first item. The Up and Down arrows, Home and End move
  between the items, Enter or Space asks for the suggestion, and Escape
  closes the menu, back to its button. After an item, the focus goes back
  to the editable area.
* The panel is a region named after the suggestion ("Rewrite"), with the
  text in it (`aria-busy` while it streams), a status ("Writing…",
  "Done", "Stopped") and its buttons: Stop while it streams, then Accept
  and Reject.
* In the editable area, `Cmd/Ctrl+Enter` accepts a suggestion that is
  done or stopped. Escape, in the editable area or in the panel, stops a
  suggestion that streams, and rejects one that is done or stopped.
* The live region says "Asked for a suggestion", "Rewrite: writing",
  "Suggestion ready: accept it with Ctrl+Enter, or reject it with
  Escape", then "Suggestion inserted", "Suggestion discarded" or
  "Suggestion stopped". It says "The suggestion was cancelled" for
  `stream_cancel/3`, and "The suggestion stopped" after 30 seconds with
  no chunk. It does not read the text as it streams: the person reads the
  panel when it is done.

## Style

`kotoba.css` styles the panel (`.kotoba-suggestion`, with
`.kotoba-suggestion-title`, `.kotoba-suggestion-status`,
`.kotoba-suggestion-content` and the buttons `.kotoba-suggestion-accept`,
`.kotoba-suggestion-reject` and `.kotoba-suggestion-stop`) and the menu
(`.kotoba-assist-menu`, `.kotoba-assist-item`) with the `--kotoba-*`
properties of the [Theming](theming.md) guide.
