# Forms and changesets

The Kotoba editor is a form field. It posts the document with the other
fields of the form, and `Kotoba.Content` casts it in the changeset.

## The field

```heex
<.form for={@form} id="post-form" phx-change="validate" phx-submit="save">
  <label id="post-body-label">Body</label>
  <.kotoba
    field={@form[:body]}
    id="post-body"
    label_id="post-body-label"
    placeholder="Write your post..."
  />
</.form>
```

`Kotoba.Components.kotoba/1` renders:

* a hidden input with the name of the field (`post[body]`). Its value is
  the JSON of the document.
* the editor element, with `phx-hook="Kotoba"` and `phx-update="ignore"`.
  The hook builds the toolbar and the editable area in it.
* the LiveView file input, when you give `uploads`.

Give the editor an accessible name: `label_id` (the id of a visible label)
is the best choice. Without it, `label` gives an `aria-label`, and the
default is the field name in words ("Body").

## What the form posts

The hook writes the document to the hidden input on every change. It also
puts the current document in the form data of `phx-change` and
`phx-submit` (through the form's `formdata` event), so these events always
have the current document, also when a patch came between the change and
the event. A plain HTML submit posts the hidden input.

The param is a JSON string. An empty editor posts the empty document, not
`""`.

## The changeset

```elixir
def changeset(post, attrs) do
  post
  |> cast(attrs, [:title, :body])
  |> validate_required([:title])
  |> validate_body()
end

# An empty editor posts an empty document, not nil, so validate_required/2
# does not see it as blank.
defp validate_body(changeset) do
  validate_change(changeset, :body, fn :body, %Kotoba.Content{doc: doc} ->
    case Kotoba.Document.parse(doc) do
      {:ok, parsed} -> if Kotoba.Document.empty?(parsed), do: [body: "can't be blank"], else: []
      {:error, _messages} -> [body: "is invalid"]
    end
  end)
end
```

`Kotoba.Content.cast/1` parses the JSON, checks every node, and renders
the HTML and the text of the document. Input that is not a valid document
casts to `:error`, so the changeset gets an `"is invalid"` error on the
field. See `Kotoba.Content` for `""`, `nil` and `empty_values`.

`Kotoba.Content` compares two values by their documents only. So a
changeset does not mark the field as changed when only the cache is new.

## Each change as an event

The form's own `phx-change` and `phx-submit` events have the document in
their params, so a form needs no other event for the editor.

For a LiveView that wants each change of the document by itself, for
example to save a draft, give the editor `change`:

```heex
<.kotoba field={@form[:body]} id="post-body" change />
```

The editor then pushes `kotoba:change` with `%{"v" => 1, "id" => id,
"doc" => envelope}` when the document changes, at most once in 300 ms
(set another time with `debounce={500}`). A LiveView that sets `change`
must handle the event:

```elixir
# Act on one editor by its id...
def handle_event("kotoba:change", %{"id" => "post-body", "doc" => doc}, socket) do
  {:noreply, save_draft(socket, doc)}
end

# ...and ignore the others.
def handle_event("kotoba:change", _params, socket), do: {:noreply, socket}
```

Without `change`, the editor pushes no `kotoba:change`. A change of
`change` in a later render turns the pushes on or off.

## Change the document from the server

The editor reads the hidden input only once, when it mounts. After that,
a new value that the server renders into the form does not change the
editor: the editor writes its own document back into the input.

To replace the document, push it:

```elixir
socket = Kotoba.Live.push_content(socket, "post-body", post.body)
```

`Kotoba.Live.push_content/3` sends `set_content`. The editor replaces its
document, clears its undo history, and does not push `kotoba:change` for
it. The other server events are in `Kotoba.Live`: `insert_node/4`,
`set_readonly/3`, `focus/2` and `remove_marker/3`. Each carries the editor
id, so only that editor acts on it.

## The hidden input after a patch

A LiveView patch of the form can put the server's old value back into the
hidden input. The hook listens for LiveView's `phx:update` event on the
document, and writes the current document into the input again after each
patch.

`phx:update` is not in the documented hook API of LiveView. `phx-change`,
`phx-submit`, form recovery and a plain submit do not depend on it: they
read the form through `formdata`, which always has the current document.
Only code that reads `input.value` directly depends on `phx:update`.

## Read-only

```heex
<.kotoba field={@form[:body]} readonly={@locked?} />
```

A change of `readonly` in a later render reaches the editor. You can also
push it with `Kotoba.Live.set_readonly/3`. Read-only is a state of the
editor in the browser only: check on the server that the person can save
the form.

## A LiveComponent

In a LiveComponent, give `phx-target={@myself}`. The editor then sends its
events (`kotoba:prompt`, and `kotoba:change` when you set `change`) to the
component, and the component must handle them:

```heex
<.kotoba field={@form[:body]} id="note-body" phx-target={@myself} />
```

## More than one editor

Give each editor its own `id`. Every event from an editor has its `id`,
and every server push names the editor, so two editors on a page do not
act on the events of the other.

## A custom toolbar

The default toolbar has every command. To choose the commands or to use
your own icons, give a `toolbar` slot:

```heex
<.kotoba field={@form[:body]} id="post-body">
  <:toolbar>
    <.kotoba_toolbar>
      <:button command="bold"><.icon name="hero-bold" /></:button>
      <:button command="link" label="Add a link"><.icon name="hero-link" /></:button>
    </.kotoba_toolbar>
  </:toolbar>
</.kotoba>
```

`Kotoba.Components.kotoba_toolbar/1` can also be outside the editor, with
`for` set to the editor id. `Kotoba.Components.toolbar_commands/0` lists
the commands.

## Testing a form

In `Phoenix.LiveViewTest`, `form/3` refuses a value for a hidden input
that differs from the rendered one, and the document is a hidden input.
Give the document in the value of `render_submit/2` or `render_change/2`,
as JSON, the way the hook sends it:

```elixir
doc = JSON.encode!(Kotoba.Content.from_markdown("Hello **world**").doc)

view
|> form("#post-form", post: %{title: "Hello"})
|> render_submit(%{post: %{body: doc}})
```

The editor's own events (`kotoba:prompt`, `kotoba:change`) go through
`render_hook/3` on the editor element, which keeps its `phx-target`:

```elixir
view
|> element("#post-body")
|> render_hook("kotoba:prompt", %{"id" => "post-body", "prompt" => "people", "query" => "ad"})

assert_push_event(view, "kotoba:prompt_results", %{items: [%{label: "Ada Lovelace"}]})
```

## Stored content without the editor

`Kotoba.Content.cast/1` also takes a map (the document envelope, or a bare
Lexical root node) and a `Kotoba.Content`. `Kotoba.Content.from_markdown/2`
makes content from Markdown, on a best-effort basis. `Kotoba.Renderer`
renders a document as HTML, text or Markdown.
