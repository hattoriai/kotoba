# Changelog

All notable changes to Kotoba are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Kotoba follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
