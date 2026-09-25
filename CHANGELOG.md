# Changelog

All notable changes to Kotoba are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Kotoba follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Repository and package skeleton for Kotoba 0.1.
- `Kotoba.Document`: reads and writes the stored document (a Lexical 0.51
  editor state in a Kotoba envelope), checks each node, keeps unknown nodes,
  and gives traversal, text, mentions and attachments.
- `Kotoba.Node`: the behaviour and `use Kotoba.Node` for node structs with
  typed fields.
- Built-in nodes under `Kotoba.Nodes` for each Lexical node of the editor,
  and the `attachment` and `mention` nodes.
- `Kotoba.Renderer`: renders a document as safe HTML (through
  `Phoenix.HTML`), as plain text, and as Markdown.
- `Kotoba.Sanitizer`: structural checks before rendering (node attributes,
  nesting, string limits), an allow list of link schemes
  (`config :kotoba, allowed_link_schemes:`), and the `:default` and
  `:untrusted` policies.
- The editor bundle (`priv/static/kotoba.esm.js` and `kotoba.cjs.js`): a
  Lexical 0.51 editor with rich text, history, lists and check lists, links
  (paste to link, `Cmd/Ctrl+K`), markdown shortcuts, highlighted code blocks,
  horizontal rules, the `attachment` and `mention` nodes, a toolbar, the
  prompt menu, the upload bridge to LiveView uploads, and app node modules.
- The `Kotoba` LiveView hook, with the `kotoba:change` and `kotoba:prompt`
  events and the `set_content`, `insert_node`, `set_readonly`, `focus` and
  `kotoba:prompt_results` server events.
- `kotoba.css` (structure, themed through `--kotoba-*` properties) and
  `kotoba-sumi.css` (the Sumi theme).
- `mix kotoba.build`: builds the bundles and copies the style sheets into
  `priv/static`.
- Toolbar icons from Lucide (ISC licence, see `NOTICE`), sized with
  `--kotoba-icon-size`.
- Links in the editor follow the server's link rule: relative URLs are kept,
  and the allowed schemes come from the hook's `data-link-schemes` attribute.
- `Kotoba.Components`: `<.kotoba>` (the editor for a form field, with the
  hidden input, prompts, app nodes and a LiveView file input),
  `<.kotoba_toolbar>` (a custom toolbar) and `<.kotoba_content>` (the cached
  HTML, or a new rendering for another policy or cache version).
- `Kotoba.Live`: `handle_prompt/3`, `consume_uploads/4`, `push_content/3`,
  `insert_node/4`, `set_readonly/3`, `focus/2` and `remove_marker/3`. Every
  push carries the editor id.
- `Kotoba.Prompts`: prompt lists (`[people: &search/1]` or
  `[{"@", :people, &search/1}]`) and their result items.
- `Kotoba.Storage` (a behaviour for file stores), `Kotoba.Storage.Local` (files
  on disk) and `Kotoba.Storage.Local.Plug` (serves them, read only).
- `Kotoba.Attachments`: keeps only the content types that the bytes of an
  uploaded file prove (PNG, JPEG, GIF, WebP, PDF, UTF-8 plain text, ZIP and
  Office files); every other file is `application/octet-stream`. It reads
  the size of the images, and removes control and bidi characters from
  file names.
- Storage keys take their extension from the checked content type, never
  from the client's file name.
- The hook sends the editor id with `kotoba:change` and `kotoba:prompt`,
  handles `remove_marker`, puts an attachment in place of its own upload
  marker (`insert_node` with a `ref`), and reads a new `data-readonly` from a
  LiveView patch.
- `mix kotoba.gen.node`: writes an app node (the `Kotoba.Node` module, the
  editor's JavaScript module in the default factory form, and a test), with
  an app-prefixed type, and prints the config and component lines.
- `mix kotoba.install`: adds the hook to `assets/js/app.js`, the style sheet
  to `assets/css/app.css` and the storage config to `config/config.exs`.
  It is idempotent, prints the lines to add when it cannot edit a file, and
  has `--dry-run`.
- `Kotoba.Renderer.escape_markdown/1`, for the Markdown of app nodes.
- `.formatter.exs` exports `field/2` and `field/3` without parentheses, for
  `import_deps: [:kotoba]`.
- `mix kotoba.gen.node` takes `--module` (the module name; the Elixir files
  follow it) and `--out` (the directory for the files).
- Tab indents a list item and Shift+Tab outdents it, wherever the caret is
  in the item. Outside a list and a code block, Tab moves the focus out of
  the editor, and so does Shift+Tab in a list item that is not indented.
- The hidden input keeps the current document after a LiveView patch of the
  form.
- The link form and the toolbar act on the selection that the page shows,
  also right after a Shift+Arrow key.
- A development server (`mix dev`, `dev.exs`) and Playwright browser tests
  (`e2e/`, `mix test.e2e`).
