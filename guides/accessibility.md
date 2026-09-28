# Accessibility

A person can do every command of the editor with the keyboard, and the
editor gives the roles and states of its parts to assistive technology.

## The name of the editor

The editable area has `role="textbox"` and `aria-multiline="true"`. Give it
a visible label, and its id as `label_id`:

```heex
<label id="post-body-label">Body</label>
<.kotoba field={@form[:body]} id="post-body" label_id="post-body-label" />
```

The editor then has `aria-labelledby`. Without `label_id`, it has an
`aria-label`: the `label` attribute, or the field name in words ("Body").
The placeholder is also in `aria-placeholder`. Give a description with
`aria-describedby`, and mark a field with an error with `aria-invalid`:
both go on the editable area, and follow each render, so an error's id
can come and go with the error:

```heex
<.kotoba
  field={@form[:body]}
  aria-invalid={@form[:body].errors != []}
  aria-describedby={if @form[:body].errors != [], do: "body-hint body-error", else: "body-hint"}
/>
```

## The toolbar

The toolbar has `role="toolbar"`, with a `group` for each set of buttons
(Text, Blocks, Lists, Insert, History). A Code group is there only while
the selection is in a code block, and a Table group only while it is in
a table.

* The toolbar is one tab stop. Tab goes to the toolbar, and Tab again goes
  to the editable area.
* The Left and Right arrows move between the buttons. Home and End go to
  the first and the last button.
* Enter or Space runs the command of the button.
* A format or block button has `aria-pressed`. A button that cannot act
  now (Undo with no history, say) has `aria-disabled="true"`.
* The title of a button shows its shortcut: `Cmd/Ctrl+B` (bold),
  `Cmd/Ctrl+I` (italic), `Cmd/Ctrl+U` (underline), `Cmd/Ctrl+Shift+H`
  (highlight), `Cmd/Ctrl+,` (subscript), `Cmd/Ctrl+.` (superscript),
  `Cmd/Ctrl+K` (link) and `Cmd/Ctrl+Z` (undo).
* An editor with fewer features (see `Kotoba.Features`) has only their
  buttons, and an extension's buttons join the toolbar with the same
  keyboard behaviour, `aria-pressed` and live region messages.
* Alt+F10 in the editable area moves the focus to the toolbar's tab stop.
  It is the way to the toolbar from a table cell, where Tab and Shift+Tab
  move between the cells.

After a command from the keyboard, the focus goes back to the editable
area, with the same selection. The command acts on the selection, so the
person can go on typing. The toolbar keeps its tab stop on the button of
the last command: Shift+Tab from the editable area goes back to it.

## Tab and Shift+Tab

The editor is not a keyboard trap.

* In a list item, Tab indents the item and Shift+Tab outdents it, where
  the caret is in the item. With a selection over several items, they
  move together. Shift+Tab in an item that is not indented moves the focus
  out of the editor.
* In a code block, Tab inserts a tab character.
* In a table cell, Tab moves to the next cell and Shift+Tab to the
  previous one. From the last cell, Tab moves the caret after the table,
  and from the first cell Shift+Tab moves it before the table.
* Everywhere else, Tab and Shift+Tab move the focus out of the editor, as
  in any form field.
* Escape takes the focus out of the editor. Then Tab goes to the next
  control of the page. Use Escape then Tab to leave a list, a code block
  or a table.

## The code language picker

In a code block, the Code group has a `<select>` named "Code language".
It is part of the toolbar's roving tab stop.

* Left and Right move to the other controls; Up and Down choose a
  language, which applies at once. The focus stays on the picker, so the
  person can try another language.
* The live region says the language ("Code language Python").
* A block in a language that the editor does not know shows it as
  "cobol (not highlighted)", and keeps it.

## Tables

The Table button inserts a table of three rows and three columns, with a
header row, and puts the caret in its first cell. In a table, the Table
group has Insert row above, Insert row below, Insert column before,
Insert column after, Header row, Header column, Delete row, Delete column
and Delete table.

* The commands act on the cell of the caret, and the caret stays in it
  when a row or a column is inserted. The live region says what happened
  ("Row inserted", "Table deleted").
* Header row and Header column have `aria-pressed`: they make the first
  row or the first column header cells.
* When the table is deleted (or the selection leaves it) while a Table
  button has the focus, the focus goes back to the editable area.
* The rendered HTML has `th scope="col"` in the header row and
  `th scope="row"` in the header column, and a first row of header cells
  in a `thead`, so a screen reader reads the header of each cell.

## The prompt menu

When a trigger (for example `@`) opens the menu:

* The menu is a `listbox`, named after the prompt ("people suggestions"),
  or with the prompt's label (see [Prompts](prompts.md)).
  The editable area has `aria-controls` with the menu's id, and
  `aria-activedescendant` with the active option.
* Up and Down move the active option. Enter or Tab inserts it. Escape
  closes the menu.

## The link form

`Cmd/Ctrl+K` or the Link button opens a small form for the URL. It keeps
the selection while the focus is in its input. Enter applies the link, and
Escape closes the form and returns to the editable area.

## Announcements

A polite live region (`role="status"`) in the editor tells the result of
actions that do not show at the caret: "Bold on", "Link applied", the
number of prompt results, "Inserted Ada Lovelace", and "Uploading
cat.png".

## Uploads

The "Attach a file" button opens the file picker. The LiveView file input
is visually hidden and out of the tab order, because the toolbar button
does the same thing. It has a label for assistive technology
(`upload_label`, "Attach files" by default). The live region tells when an
upload starts.

## Attachments and mentions

Attachments and mentions are single units in the text. Backspace before
the caret, or Delete after it, removes one. An image attachment renders
with its file name as the `alt` text.

## Motion

When the person asks for reduced motion (`prefers-reduced-motion:
reduce`), the editor has no transitions, animations or smooth scrolling.
