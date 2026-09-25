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
