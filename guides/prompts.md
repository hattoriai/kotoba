# Prompts and mentions

A prompt is a trigger character in the editor, for example `@`. When the
person types the trigger at the start of a line or after a space, a menu
opens under the caret. The text after the trigger is the query. The
LiveView finds the results, and the person selects one. The editor then
inserts a mention: a `Kotoba.Nodes.Mention` node with a `kind`, an `id`
and a `label`.

## A prompt list

```elixir
# The first prompt has the trigger "@", the second has "#".
[people: &MyApp.People.search/1, work: &MyApp.Work.search/1]

# Each trigger given explicitly.
[{"@", :people, &MyApp.People.search/1}, {"#", :work, &MyApp.Work.search/1}]
```

A trigger is one character that is not white space. The name of a prompt
is the `kind` of the mentions that it inserts. For more than two prompts,
give each trigger explicitly. See `Kotoba.Prompts`.

## The menu's name

Screen readers announce the menu by its name, "people suggestions" (the
prompt name) unless the prompt has a label. To give it one, put the
callback in a tuple with `label:`:

```elixir
[people: {&MyApp.People.search/1, label: "People in the workshop"}]

[{"#", :work, {&MyApp.Work.search/1, label: "Work items"}}]
```

A label is a non-empty string of at most 200 characters, with no control
characters.

## The LiveView

```elixir
def mount(_params, _session, socket) do
  {:ok, assign(socket, form: to_form(%{}, as: :post))}
end

def render(assigns) do
  ~H"""
  <.form for={@form} phx-change="validate">
    <.kotoba field={@form[:body]} id="post-body" prompts={prompts(@current_scope)} />
  </.form>
  """
end

def handle_event("validate", %{"post" => params}, socket) do
  {:noreply, assign(socket, form: to_form(params, as: :post))}
end

def handle_event("kotoba:prompt", params, socket) do
  prompts = prompts(socket.assigns.current_scope)
  {:noreply, Kotoba.Live.handle_prompt(socket, params, prompts)}
end

defp prompts(scope) do
  [people: fn query -> MyApp.People.search(scope, query) end]
end
```

Give the same prompt list to the component and to
`Kotoba.Live.handle_prompt/3`. The component sends only the triggers and
the names to the browser. The functions run in the LiveView process.

A callback of arity 2 also gets the socket:

```elixir
[people: fn query, socket -> MyApp.People.search(socket.assigns.current_scope, query) end]
```

## The results

The callback gets the query and returns a list of items. An item is:

* a map with `:id` (a string or an integer), `:label` (a string), and an
  optional `:hint` (a string), with atom or string keys, or
* an `{id, label}` tuple.

```elixir
def search(scope, query) do
  scope
  |> list_people(query)
  |> Enum.map(&%{id: &1.id, label: &1.name, hint: &1.title})
end
```

Kotoba drops items that do not have this shape, and sends at most 50. It
removes control characters (such as a tab or a line break) from the id,
the label and the hint. The reply has the query, so the editor drops
results that come after a newer query.

A callback that raises, exits or throws, or that returns anything but a
list (for example `{:ok, items}`), gives no items. Kotoba logs a warning
with the prompt name, the menu shows "No results", and the LiveView keeps
running.

The callback runs for each query while the person types, in the LiveView
process: a slow callback blocks the LiveView while it runs. Keep it fast,
and limit the results in the query itself.

## The query

The query is the text between the trigger and the caret. It has at most
64 characters, and it cannot have white space: a space closes the menu.
So a query finds "Ada" but not "Ada Lovelace". Search on the start of
each word, or on a handle with no spaces.

## The keys

* Up and Down move the active option.
* Enter or Tab inserts the mention of the active option.
* Escape closes the menu.

The menu is a `listbox`, with `aria-activedescendant` on the editable
area, and a live region tells the number of results. See the
[Accessibility](accessibility.md) guide.

## The stored mentions

A mention renders as
`<span class="kotoba-mention" data-kind="people" data-id="1">Ada</span>`,
and as its label in text and Markdown. `Kotoba.Document.mentions/1` gives
the mentions of a document, for example to notify the people mentioned in
a saved post:

```elixir
{:ok, doc} = Kotoba.Document.parse(post.body.doc)

for %Kotoba.Nodes.Mention{kind: "people", id: id} <- Kotoba.Document.mentions(doc) do
  MyApp.Notifications.mentioned(id, post)
end
```

The `id` of a mention comes from the browser, as the other content does.
Check on the server that the person can mention that thing before you
act on it.
