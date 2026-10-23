# Prompts and mentions

A prompt is a trigger character in the editor, for example `@`. When the
person types the trigger at the start of a line or after a space, a menu
opens under the caret. The text after the trigger is the query. The
LiveView finds the results (or the editor, from a list that it has), and
the person selects one. The editor then inserts a mention: a
`Kotoba.Nodes.Mention` node with a `kind`, an `id` and a `label`. A prompt
can insert text (an emoji, a snippet) or a node of your app instead.

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

## Options

A prompt is a callback, a callback with options, or a keyword list with
the callback (`search:`) or a list of items (`items:`):

```elixir
[
  {"@", :people, [search: &MyApp.People.search/1, spaces: true, min_length: 2]},
  {":", :emoji, [items: MyApp.Emoji.items(), insert: :text, label: "Emoji"]},
  {"+", :tags, [search: &MyApp.Tags.search/1, insert: {:node, "my-app-tag"}, async: true]}
]
```

| Option | Default | |
| --- | --- | --- |
| `label` | "<name> suggestions" | the accessible name of the menu, below |
| `spaces` | `false` | the query can have spaces, below |
| `min_length` | `0` | the characters of the query before the first search |
| `max_length` | `64` | the longest query, up to 200 characters |
| `insert` | `:mention` | `:mention`, `:text`, `{:node, type}` or `:command`, below |
| `with_text` | `:below` | an insert menu in a block with text: `:below` or `:turn_into`, below |
| `async` | `false` | the search runs in a task, below |

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
`Kotoba.Live.handle_prompt/3`. The component sends the triggers, the
names, the labels and the options to the browser, and the `items` of a
local prompt; the search functions stay on the server and run in the
LiveView process.

A callback of arity 2 also gets the socket:

```elixir
[people: fn query, socket -> MyApp.People.search(socket.assigns.current_scope, query) end]
```

## Local items

A prompt with `items:` needs no server. The component gives the items to
the editor (at most 500), and the editor filters them as the person types:
each word of the query must start a word of the label or the hint, with
no regard to case or accents, and the labels that start with the query
come first. `Kotoba.Prompts.filter/2` does the same in Elixir.

```elixir
@emoji [
  %{id: "tada", label: "tada", hint: "🎉", text: "🎉"},
  %{id: "thumbsup", label: "thumbs up", hint: "👍", text: "👍"}
]

[{":", :emoji, [items: @emoji, insert: :text]}]
```

The items are in the page, so give only the ones that the person can
see.

## What a result inserts

* `insert: :mention` (the default) inserts a mention of the prompt's
  `kind`, and a space.
* `insert: :text` inserts the item's `:text` (its label when it has
  none), and a space: an emoji, a snippet, a signature.
* `insert: {:node, type}` inserts a node of your app, of the Lexical
  `type`, built from the item's `:attrs` as `importJSON` reads them (the
  node needs to be in the editor, see the [Custom nodes](custom_nodes.md)
  guide). An inline node gets a space after it.

```elixir
def search_tags(query) do
  for tag <- MyApp.Tags.search(query) do
    %{id: tag.id, label: tag.name, attrs: %{label: tag.name}}
  end
end

[{"+", :tags, [search: &search_tags/1, insert: {:node, "my-app-tag"}]}]
```

When the editor cannot make the node (a type it does not have, or
attributes that `importJSON` refuses), it logs the error in the console,
inserts nothing, and says "Could not insert …".

* `insert: :command` makes the prompt an insert menu, next.

## The insert menu

An insert menu is a prompt whose items run a command of the editor:
typed at the start of a line or after a space, `/` opens a menu of what
the field can insert or turn the block into, filtered as the person types
(`/h2`, `/table`, `/board`). A field has one only when it asks for it:

```heex
<.kotoba field={@form[:body]} prompts={[{"/", :insert, insert: :command, label: "Insert"}]} />
```

Its items are, by default, the editor's own:

* the built-in items of the field's features (`Kotoba.Prompts.commands/1`),
  in the Basic group: Text, Heading 1 to 4, Quote, Bulleted list,
  Numbered list, Check list, Code block, Table and Divider; Image or file
  (Media) with `uploads`, and Embed (Embeds) with `embeds`, which opens
  the app's picker. A field without `tables` has no Table;
* the extensions' items: their blocks with a label (a callout, see the
  [Extensions](extensions.md) guide) and their insert items.

The order and the groups are the app's: `:builtin` and `:extensions` in
the prompt's `:items` stand for these, at their place, among the app's
own items. An app leaves out the built-in items by leaving out
`:builtin`.

```elixir
@insert [
  items: [
    :builtin,
    %{id: "board", label: "Board", group: "Embeds", node: %{type: "embed", kind: "board", ref: "new"}},
    %{id: "signature", label: "Signature", group: "Snippets", text: "— The team", keywords: ["sign"]},
    :extensions
  ],
  insert: :command,
  label: "Insert"
]

prompts={[people: &MyApp.People.search/1, {"/", :insert, @insert}]}
```

An item has one of:

* `:command`: a built-in command (`"paragraph"`, `"h1"` to `"h4"`,
  `"quote"`, `"bullet"`, `"number"`, `"check"`, `"code-block"`,
  `"table"`, `"rule"`, `"upload"`, `"embed"`), an extension's block
  (`"ext:<type>"`) or an extension's insert item
  (`"<extension>:<command>"`). An app gives the built-in commands its own
  labels with items of its own: `%{id: "h1", label: "Titre", command:
  "h1", group: "Texte"}`;
* `:node`: a node, as a document has it (a map with a `"type"`, at most
  2048 bytes of JSON): an embed, a node of the app. A block takes the
  place of an empty paragraph, or goes below the block; an inline node
  goes at the caret;
* `:text`: text, at the caret (a snippet, a template line).

and may have a `:group` (a heading over its items, where it changes) and
`:keywords`, words that find it besides its label: `/title` finds
Heading 1.

The item runs where the trigger was, after the trigger and the query are
removed, in one change: one undo step. A block of text turns an empty
paragraph into it; in a block with text it goes below (`with_text:
:below`, the default) or the block turns into it (`with_text:
:turn_into`). The menu leaves out an item whose command or node needs a
feature, a node type, uploads or embeds that the field does not have,
and `Kotoba.Content.validate_features/3` still refuses a document with
another feature.

A `:search` callback gives an insert menu its items from the server, as
any prompt: `Kotoba.Prompts.filter(Kotoba.Prompts.commands(), query)`
finds the built-in ones. The extensions' items are only in a menu with
`:items`.

The Markdown shortcuts stay (`## ` makes a heading): the menu is for the
people who do not know them. With the `blocks` feature (see the [Editing
features](features.md) guide), the `+` beside a block opens the menu in
a new paragraph below it.

## Slow searches

The search of a prompt runs in the LiveView process: while it runs, the
LiveView answers nothing else. For a search that can be slow (a remote
API, a large table), give the prompt `async: true`. `Kotoba.Live.handle_prompt/3`
then runs it in a task (`Phoenix.LiveView.start_async/3`), and the
LiveView gives its result to `Kotoba.Live.handle_prompt_async/3`:

```elixir
def handle_async({:kotoba_prompt, _id, _prompt, _query} = name, result, socket) do
  {:noreply, Kotoba.Live.handle_prompt_async(socket, name, result)}
end
```

The callback of an async prompt takes only the query: read what it needs
from the socket when you build the prompt list.

In the editor, the menu says "Searching…" while it waits. It keeps the
answers of the menu's queries, so going back to a query (Backspace)
shows its results at once, and it drops an answer to an older query. A
query with no answer after 8 seconds gives "Results did not load". The
person can go on typing all the while.

## The results

The callback gets the query and returns a list of items. An item is:

* a map with `:id` (a string or an integer), `:label` (a string), and
  the optional `:hint` (a string, shown next to the label), `:text` (what
  an `insert: :text` prompt inserts) and `:attrs` (the attributes of the
  node of an `insert: {:node, type}` prompt: a map that encodes to JSON in
  at most 2048 bytes), with atom or string keys, or
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
list (for example `{:ok, items}`), fails. Kotoba logs a warning with the
prompt name, the reply has `error: true`, the menu shows "Results did not
load", and the LiveView keeps running.

The callback runs for each query while the person types. Keep it fast,
and limit the results in the query itself; give a slow one `async: true`.

## The query

The query is the text between the trigger and the caret. It has at most
64 characters (`max_length`, up to 200), and by default no white space: a
space closes the menu, so a query finds "Ada" but not "Ada Lovelace".

With `spaces: true`, the query can have spaces: "@Ada Lov" searches "Ada
Lov". The query ends at two spaces in a row (or a line break), and it
cannot start with a space ("@ Ada" is no query). A space at its end is not
searched: "@Ada " searches "Ada", so the results stay while the person
types the next word.

With `min_length: 2`, the menu says "Keep typing to search" until the
query has two characters, and nothing is searched before.

## The keys

* Up and Down move the active option.
* Enter or Tab inserts the active option.
* Escape closes the menu; it stays closed for that trigger.

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
