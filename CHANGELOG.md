# Changelog

All notable changes to Kotoba are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Kotoba follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Features: `<.kotoba features={~w(bold italic links lists)}>` gives an
  editor only those built-in features (`Kotoba.Features`: bold, italic,
  strikethrough, inline_code, links, headings, quotes, lists, check_lists,
  code_blocks, horizontal_rules, tables, attachments, mentions). A feature
  that is off has no node, toolbar button, Markdown shortcut or keyboard
  shortcut; pasted content of it comes in as paragraphs and text, and a
  stored node of it is kept as an unknown node. With no list, an editor
  has every feature, as before.
- `Kotoba.Content.validate_features/3` refuses, in a changeset, a document
  with a feature that the field does not have; `Kotoba.Features.used/1`
  and `check/2` read the features of a document.
- Extensions: `<.kotoba extensions={[url]}>` loads JavaScript modules that
  add nodes, `register` (commands, transforms, listeners, with a cleanup),
  Markdown shortcuts and toolbar controls (`<extension>:<command>`, with
  `aria-pressed`, visibility and the live region) to an editor. The
  built-in features are extensions of the same form. A module that fails
  to load or register is logged, and the editor mounts with the rest. See
  the Extensions guide, and the example callout extension of the
  development server.
- `kotoba_toolbar` takes an extension's command in a `button` slot.

- A code language picker: in a code block, the toolbar has a "Code
  language" `<select>` with plain text and 28 languages (Bash, C, C++,
  CSS, Diff, Dockerfile, Elixir, Erlang, Go, GraphQL, HTML, Java,
  JavaScript, JSON, Kotlin, Markdown, Objective-C, PHP, PowerShell,
  Python, Ruby, Rust, SQL, Swift, TOML, TypeScript, XML, YAML). The
  editor bundles the grammars of Dockerfile, Erlang, GraphQL, Kotlin,
  PHP, Ruby, TOML and YAML too, and highlights the aliases (`ex`, `yml`,
  `js`...). A block keeps the language name that it has until the person
  picks one; a name that is no language shows as "(not highlighted)".
- `Kotoba.CodeLanguages`, the table of the languages, their labels and
  their aliases, and the `code_languages` attribute of `<.kotoba>` to
  choose the languages of an editor's picker.
- The `code-language` toolbar command, a `<select>` in a custom toolbar.
- Tables. The Table button inserts a table with a header row. In a table,
  a Table group in the toolbar inserts and deletes rows and columns,
  toggles a header row and a header column, and deletes the table. Tab
  and Shift+Tab move between the cells; Escape then Tab leaves the
  editor, as in a list. Pasted HTML tables become tables (merged cells
  are split and cell colours dropped); a table in a table is not allowed.
- `Kotoba.Nodes.Table`, `Kotoba.Nodes.TableRow` and
  `Kotoba.Nodes.TableCell` read the JSON of `@lexical/table`. The HTML is
  a `table.kotoba-table` in a `div.kotoba-table-scroll`, with a `thead`
  for a header row and `th` with `scope`; the text has a line for each
  row; the Markdown is a GitHub Flavored Markdown table. The sanitizer
  keeps a table under the root, rows in tables and cells in rows. The
  editor's layout keys (column widths, cell colours) round-trip and are
  not rendered.
- Alt+F10 in the editor moves the focus to the toolbar, the way to the
  table controls from a cell.
- `Kotoba.Renderer.text_each/2`, the text counterpart of `markdown_each/2`.
- The toolbar commands `table`, `table-row-before`, `table-row-after`,
  `table-column-before`, `table-column-after`, `table-header-row`,
  `table-header-column`, `table-delete-row`, `table-delete-column` and
  `table-delete`.
- A prompt can have a label, the accessible name of its menu:
  `prompts={[people: {fun, label: "People in the workshop"}]}`. Without
  one, the menu is still named "<prompt> suggestions".
  `Kotoba.Prompts.labels/1` gives the labels, and the component sends
  them to the editor as `data-prompt-labels`.

### Changed

- The editor bundle is about 24 KB larger (8 KB with gzip), for features
  and extensions: `@lexical/utils` and `@lexical/selection` are whole in
  it, for the extensions.
- A code block with no language is plain text in the editor, as in the
  HTML. Lexical highlighted it as JavaScript.
- The editor bundle is about 25 KB larger (7 KB with gzip), for the new
  grammars.
- `table`, `tablerow` and `tablecell` are built-in node types now, so an
  app node cannot have one of these types.
- The editor bundle is about 70 KB larger (20 KB with gzip), for
  `@lexical/table`.

### Fixed

- `mix kotoba.install` finds the Kotoba package in the project's deps
  directory (`Mix.Project.deps_path/0`), not in `deps/`. In an umbrella
  child or with `MIX_DEPS_PATH`, a Hex dependency is no longer called a
  path dependency, and the style sheet imports and the `NODE_PATH` note
  point at the right directory.

## [0.1.0] - 2026-09-25

The first release.

### Added

- The editor bundle (`priv/static/kotoba.esm.js` and `kotoba.cjs.js`): a
  Lexical 0.51 editor with rich text, history, headings, quotes, lists and
  check lists, links (paste to link, `Cmd/Ctrl+K`, relative URLs and the
  server's allowed schemes), markdown shortcuts, highlighted code blocks,
  horizontal rules, attachments, mentions, a toolbar with Lucide icons, the
  prompt menu, the upload bridge to LiveView uploads, and app node modules.
  The host app does not need Node.js.
- The `Kotoba` LiveView hook. It pushes `kotoba:prompt`, and handles
  `set_content`, `insert_node`, `remove_marker`, `set_readonly`, `focus`
  and `kotoba:prompt_results`. Every message carries the editor id. The
  hidden input and the form data of `phx-change` and `phx-submit` always
  have the current document.
- `kotoba:change` is opt-in: the editor pushes it only with the `change`
  attribute of `<.kotoba>`. A LiveView with an editor needs no
  `kotoba:change` clause unless it sets `change`.
- The editable area follows the field's `aria-invalid` and
  `aria-describedby` on every render (LiveView patches only data
  attributes of the editor element, so the component passes them there).
- Keyboard operation of every command: a toolbar with one tab stop and
  arrow keys, Tab and Shift+Tab in lists, Tab in code blocks, Escape to
  leave the editor, a prompt menu as a `listbox`, and a polite live region.
- `kotoba.css` (structure, themed through `--kotoba-*` properties) and
  `kotoba-sumi.css` (the Sumi theme, with dark and light through
  `data-theme` and `prefers-color-scheme`). A mention has its own
  `--kotoba-mention-text` and `--kotoba-mention-background`; in the Sumi
  theme it is ink on a quiet tint, so it never reads as the blade that a
  Sumi page keeps for what needs attention.
- `Kotoba.Content`: an Ecto type that stores the document with its cached
  HTML and text, with `rerender/2` and `from_markdown/2`.
- `Kotoba.Document`: parses and checks a document, keeps unknown nodes, and
  gives traversal, text, mentions and attachments.
- `Kotoba.Node` (`use Kotoba.Node` with typed fields), the built-in nodes
  under `Kotoba.Nodes`, and the node registry.
- `Kotoba.Renderer`: safe HTML through `Phoenix.HTML`, plain text, and
  Markdown, with `escape_markdown/1` for the Markdown of app nodes.
- `Kotoba.Sanitizer`: structural checks of attributes, nesting and URLs,
  the allowed link schemes (`config :kotoba, allowed_link_schemes:`), and
  the `:default` and `:untrusted` policies.
- `Kotoba.Components`: `<.kotoba>`, `<.kotoba_toolbar>` and
  `<.kotoba_content>`.
- `Kotoba.Live`: `handle_prompt/3`, `consume_uploads/4`, `push_content/3`,
  `insert_node/4`, `set_readonly/3`, `focus/2` and `remove_marker/3`.
- `Kotoba.Prompts`: prompt lists with one-character triggers.
- `Kotoba.Attachments`: keeps only the content types that the bytes of a
  file prove, and cleans file names.
- `Kotoba.Storage` (a behaviour), `Kotoba.Storage.Local` and
  `Kotoba.Storage.Local.Plug` (serves the files with safe headers).
- `mix kotoba.install`, `mix kotoba.gen.node`, and, for work on Kotoba
  itself, `mix kotoba.build` and `mix kotoba.release_check`. The installer
  also sets up an app that has Kotoba as a path dependency: its `app.css`
  imports point at the dependency's directory, and it prints the
  `NODE_PATH` entry that esbuild needs for it.
- `.formatter.exs` exports `field/2` and `field/3` for `import_deps`.
- Guides: quickstart, forms, uploads, prompts, custom nodes, theming,
  security, accessibility and known limits.

[Unreleased]: https://github.com/hattoriai/kotoba/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/hattoriai/kotoba/releases/tag/v0.1.0
