# Editing features

This guide is the tour of what the editor does, and how to choose it for
each field: the built-in features, their toolbar buttons, keyboard and
Markdown shortcuts, colors, links, code blocks, tables, and the toolbar
itself. To see them all at once, run the development server of this
repository (`mix dev`, see the README).

## The features

Each built-in feature is a part of the editor that a field can have or
not (`Kotoba.Features`):

| Feature | What it is | Toolbar | Keyboard | Markdown |
| --- | --- | --- | --- | --- |
| `bold` | bold text | Bold | `Cmd/Ctrl+B` | `**text**`, `__text__` |
| `italic` | italic text | Italic | `Cmd/Ctrl+I` | `*text*`, `_text_` |
| `underline` | underlined text | Underline | `Cmd/Ctrl+U` | |
| `strikethrough` | struck text | Strikethrough | | `~~text~~` |
| `highlight` | highlights and text colors | Highlight (the palette) | `Cmd/Ctrl+Shift+H` | `==text==` |
| `subscript` | subscript text | (an app's toolbar) | `Cmd/Ctrl+,` | |
| `superscript` | superscript text | (an app's toolbar) | `Cmd/Ctrl+.` | |
| `inline_code` | code in a line | Inline code | | `` `code` `` |
| `links` | links and autolinks | Link | `Cmd/Ctrl+K` | `[text](url)` |
| `headings` | headings 1 to 4 | Heading 1 to 4 | | `# ` to `#### ` |
| `quotes` | block quotes | Quote | | `> ` |
| `lists` | bulleted and numbered lists | Bulleted list, Numbered list | Tab, Shift+Tab | `- `, `* `, `+ `, `1. ` |
| `check_lists` | check lists (needs `lists`) | Check list | Space on a focused box | `[ ] `, `[x] `, `- [ ] ` |
| `code_blocks` | code blocks, highlighted, with a language picker | Code block, Code language | Tab inserts a tab | ` ``` `, ` ```elixir ` |
| `horizontal_rules` | horizontal rules | Horizontal rule | | `---`, `***`, `___` |
| `tables` | tables | Table, and the Table group | Tab, Shift+Tab | |
| `attachments` | files and images (with `uploads`) | Attach a file | drop, paste | |
| `mentions` | prompts and mentions (with `prompts`) | | the trigger | |

`Cmd` is the key on a Mac, `Ctrl` elsewhere. A Markdown shortcut acts as
you type it: `## ` at the start of a line makes a heading, and
`**bold**` becomes bold when you type the last `*`. `***text***` makes
bold and italic text.

Paragraphs, line breaks (`Shift+Enter`), tabs, undo (`Cmd/Ctrl+Z`) and
redo (`Cmd/Ctrl+Shift+Z`) are always there. The case formats
(`lowercase`, `uppercase`, `capitalize`) are not features: the editor
keeps them when they come in a pasted text or a stored document.

## Choose the features of a field

With no `features`, an editor has every feature. Give a list for fewer:

```heex
<.kotoba field={@form[:comment]} id="comment" features={~w(bold italic links lists mentions)} />
<.kotoba field={@form[:body]} id="body" />
```

A feature that is off is not in the editor at all:

* its buttons are not in the default toolbar, and are hidden in a custom
  one;
* its Markdown shortcut types the text, and its keyboard shortcut does
  nothing;
* pasted content of it comes in as plain paragraphs and text: a pasted
  table, heading or code block is paragraphs, and a pasted format is
  dropped;
* a stored node of it loads as an unknown node: the editor shows its type
  in a placeholder, and saves it with no change.

`attachments` needs `uploads` too (see the [Uploads](uploads.md) guide),
and `mentions` needs `prompts` (see [Prompts and mentions](prompts.md)).

### Check them on the server

The editor keeps out what it does not have, but a request can post any
document. Check the field in its changeset:

```elixir
def changeset(comment, attrs) do
  comment
  |> cast(attrs, [:body])
  |> Kotoba.Content.validate_features(:body, ~w(bold italic links lists mentions)a)
end
```

A document with another feature gets the error
`"has content that is not allowed: tables"` (with `validation: :features`
and the names in the error's keys). `Kotoba.Features.used/1` and
`Kotoba.Features.check/2` read the features of a `Kotoba.Document`. App
nodes are not features: the check allows them.

## Text formats and colors

The Text group of the default toolbar has Bold, Italic, Underline,
Strikethrough, Highlight and Inline code. A format button has
`aria-pressed`, and the live region says "Bold on" or "Bold off".

Subscript and superscript are features with their keyboard shortcuts, but
have no button in the default toolbar. An app's toolbar can have them
(`command="subscript"`, `command="superscript"`, see below). Turning one on
turns the other off.

The Highlight button opens the color palette: seven text colors, seven
highlights (red, orange, yellow, green, blue, purple and gray) and
"Remove color". `Cmd/Ctrl+Shift+H` and `==text==` give the default
highlight, yellow. Text colors are part of the `highlight` feature.

The document stores a color as its name, never as a CSS value, and the
HTML has classes: `span.kotoba-color-red` and
`mark.kotoba-highlight-green` (the default highlight is a plain `mark`).
`kotoba.css` gives each name a color that reads on light and dark
backgrounds; the [Theming](theming.md) guide shows how to set your own.
`Kotoba.Nodes.Text.colors/1` reads the colors of a text node, and
`Kotoba.Nodes.Text.palette/0` gives the names.

## Links

The Link button or `Cmd/Ctrl+K` opens a small form for the URL of the
selected text. Enter applies it, an empty URL removes the link, and
Escape closes the form. Pasting a URL over selected text makes a link, and
the editor links the URLs and email addresses that you type (autolinks).

A link can be relative (`/docs`, `#part`) or have an allowed scheme:
`http`, `https` and `mailto` by default. To allow others:

```elixir
config :kotoba, allowed_link_schemes: ~w(http https mailto tel)
```

A link with another scheme becomes its text, in the editor and in the
HTML. The HTML of a link has `rel="noopener nofollow"`.

## Lists and check lists

Tab indents a list item and Shift+Tab outdents it (in an item that is not
indented, Shift+Tab leaves the editor). In a check list, a click on the
box, or Space when the box has the focus, checks the item. The HTML of a
check list is `ul.kotoba-check`, with `li.kotoba-checked` and
`li.kotoba-unchecked` items, which `kotoba.css` draws with a box.

## Code blocks

In a code block, the toolbar shows the code language picker. It offers
plain text and the 28 languages of `Kotoba.CodeLanguages`, and the editor
highlights the code as you type. ` ```elixir ` at the start of a line
makes a code block in that language. To offer fewer languages, give their
ids or aliases:

```heex
<.kotoba field={@form[:body]} id="post-body" code_languages={~w(elixir erlang sql bash)} />
```

A name that is not a language, and an empty list, raise `ArgumentError`.
The list chooses what the picker offers, not what the editor keeps: a
pasted or stored block in another language keeps its language, is
highlighted when the editor knows it, and shows in the picker.

The HTML of a code block is `pre` with `code.language-<language>`, and
no highlighting. To highlight rendered code, use a highlighter of your own
on the page, for example Prism with a Prism theme: the editor's own copy of
Prism does not touch the page's `window.Prism` (see the
[Theming](theming.md) guide).

## Tables

The Table button inserts a table of three rows and three columns, with a
header row. In a table, the Table group of the toolbar has Insert row
above, Insert row below, Insert column before, Insert column after,
Header row, Header column, Delete row, Delete column and Delete table. Tab
and Shift+Tab move between the cells; Alt+F10 goes to the toolbar.

A pasted HTML table becomes a table. The editor has no command to merge
cells, but it keeps the merged cells of a pasted or stored table
(`colspan`, `rowspan`).

The HTML is a `table.kotoba-table` in a `div.kotoba-table-scroll` (which
scrolls a wide table sideways), with a `thead` for a header row and
`th scope="col"` or `th scope="row"` for header cells. `kotoba.css` styles
it. The Markdown of a table is a GitHub Flavored Markdown table, with the
limits in the [Known limits](limits.md) guide.

## The toolbar

The default toolbar has the buttons of the editor's features, in groups:
Text (formats and Link), Blocks (headings and Quote), Lists, Insert (Code
block, Horizontal rule, Table, Attach a file), the extensions' buttons,
and History (Undo, Redo). The Code group (the language picker) shows in a
code block, and the Table group in a table. The toolbar is one tab stop,
with the arrow keys between the buttons (see the
[Accessibility](accessibility.md) guide).

### A custom toolbar

To choose the buttons, their order or their icons, give a `toolbar` slot
with `Kotoba.Components.kotoba_toolbar/1`:

```heex
<.kotoba field={@form[:body]} id="post-body">
  <:toolbar>
    <.kotoba_toolbar>
      <:button command="bold"><.icon name="hero-bold" /></:button>
      <:button command="italic"><.icon name="hero-italic" /></:button>
      <:button command="link" label="Add a link"><.icon name="hero-link" /></:button>
      <:button command="subscript" label="Subscript" class="my-button">x₂</:button>
      <:button command="undo"><.icon name="hero-arrow-uturn-left" /></:button>
    </.kotoba_toolbar>
  </:toolbar>
</.kotoba>
```

Each `button` slot has a `command`, an optional `label` (the accessible
name and the title; the command's own label by default) and an optional
`class`. With no slots, `commands` gives text buttons for a list of
commands:

```heex
<.kotoba_toolbar commands={~w(bold italic underline highlight subscript superscript undo redo)} />
```

`Kotoba.Components.toolbar_commands/0` lists the commands: `bold`,
`italic`, `underline`, `strikethrough`, `highlight`, `code`,
`subscript`, `superscript`, `link`, `h1` to `h4`, `quote`, `bullet`,
`number`, `check`, `code-block`, `rule`, `table`, `upload`,
`code-language`, the `table-*` commands, `undo` and `redo`. An
extension's control is `<extension>:<command>` (see the
[Extensions](extensions.md) guide). Another command raises
`ArgumentError`.

* The editor adds `role="toolbar"`, the roving tabindex, `aria-pressed`
  and `aria-disabled`; `label` names the toolbar ("Formatting" by
  default), and `class` adds classes.
* The buttons of a feature that the editor does not have are hidden.
* The `table-*` buttons are hidden when the selection is not in a table.
* `code-language` renders a `<select>`, the code language picker: the
  editor fills it, and shows it in a code block.
* `highlight` opens the color palette.

A toolbar can also be outside the editor, anywhere on the page, with
`for` set to the editor's id:

```heex
<.kotoba_toolbar for="post-body" commands={~w(bold italic link)} />
<.kotoba field={@form[:body]} id="post-body" />
```

## More

* [Prompts and mentions](prompts.md): `@` menus, emoji, tags.
* [Uploads](uploads.md): files and images in the document.
* [Custom nodes](custom_nodes.md) and [Extensions](extensions.md): your
  own nodes, commands, buttons and shortcuts.
* [Rendering](rendering.md): the HTML, text and Markdown of a document.
