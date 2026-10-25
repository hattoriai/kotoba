# Changelog

All notable changes to Kotoba are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Kotoba follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The Sumi theme follows Sumi's seven themes and their accents. The
  palette's names keep their hue in each: `orange` is Sumi's orange, not
  the theme's ember. A code token of the accent's hue is orange instead
  (Smoke's strings, Snow's functions), and the code's strings, functions,
  insertions and deletions are the palette's green, blue and red, mixed
  with the text for AA. `mix dev` shows the editor in each
  (`?sumi=smoke&sample=palette`). See the Theming guide.
- A shared editor's place says what is selected: its `"label"` is the
  first words of the selected text (a caret has none), for a person's
  selection and an agent's (Issho's labels, hattoriai/issho#32). Issho
  shows it to agents and in its panels; an Issho before labels ignores it.

### Fixed

- The Sumi theme gave Sumi's dark themes other than Ink the light
  palette, and Sumi's light themes other than Paper the dark one on a
  system in dark mode. Its orange was the theme's ember: jade in Smoke,
  gold in Stone, vermilion in Lacquer, indigo in Snow and pink in Silk.
- The default highlight (a plain `mark`) was the browser's yellow with
  black text, in the editor and in rendered content, in every theme; it
  is `--kotoba-highlight`.

## [0.8.0] - 2026-10-24

Uploads kept with Storehouse; on Issho 0.4: comments written in the
editor, and a document's changes as events.

### Changed (breaking)

- Shared editors need `{:issho, "~> 0.4.2"}`, from Hex. An editor that is
  not shared needs nothing.

### Changed

- Uploads take Storehouse 0.2 (`{:storehouse, "~> 0.2"}`, which
  `mix kotoba.install` adds): its security changes, and requests made with
  Req. A HEIF file is now `image/heic`, by its bytes, not
  `application/octet-stream`.
- Uploads keep their files with [Storehouse](https://hexdocs.pm/storehouse),
  Kotoba's storage taken out into a library of its own: each file is
  checked by its bytes (`Kotoba.Attachments.describe/2` is
  `Storehouse.Check`'s, and reads a JPEG's EXIF orientation), stored under
  a new key, and served by `Storehouse.Local.Plug`. Uploads go to
  Storehouse's store, `config :storehouse, adapter: ...`: the local disk
  (`Storehouse.Local`), S3 and the stores that speak its API
  (`Storehouse.S3`: R2, MinIO, Tigris, LocalStack), or one of the app's.
  An app that keeps other files with Storehouse keeps Kotoba's in the
  same store. `mix kotoba.install` configures Storehouse.
- Storehouse is an optional dependency: `Kotoba.Live.consume_uploads/4`,
  `Kotoba.Attachments` and `Kotoba.Storage` are there when the app has
  `{:storehouse, "~> 0.2"}` in its deps. An editor without uploads needs
  nothing.

### Deprecated

- `Kotoba.Storage.Local`, `Kotoba.Storage.Local.Plug`,
  `config :kotoba, storage: ...`, and `Kotoba.Storage`'s `key/2`,
  `safe_name/2` and `valid_key?/1`. They still work, with deprecation
  warnings, and are removed in Kotoba 1.0.

### Upgrading

See the Upgrading guide, "To Kotoba 0.8". An app with uploads:

1. Adds `{:storehouse, "~> 0.2"}` to its deps.
2. Replaces `config :kotoba, Kotoba.Storage.Local, ...` with
   `config :storehouse, Storehouse.Local, ...`, with the same `root`, and
   `url_prefix: "/uploads/kotoba"` (the old default, unless it gave
   another), so that the URLs in its documents stay valid.
3. Removes `config :kotoba, storage: Kotoba.Storage.Local`. A store of its
   own goes in `config :storehouse, adapter: MyApp.Store`, with
   `@behaviour Storehouse.Adapter` in place of `@behaviour Kotoba.Storage`
   (the callbacks are the same).
4. Replaces `Kotoba.Storage.Local.Plug` with `Storehouse.Local.Plug`, and
   `Kotoba.Storage`'s `key/2` with `Storehouse.key/2`.

Until it does, step 1 is the only one it needs: the rest works as it did,
and says what to change.

### Added

- A Kotoba editor as the comment box of Issho's comments
  (`Issho.Components.comments/1`'s `:input` slot): `Kotoba.Issho.read_comment/1`
  is its `read`, `comment_prompts/2` its `@` of the room's people and
  `mentionable`, and `comment_field/3` its field, so that an edit starts
  from the comment as it is. A mention is `"@"` and the person's name in
  the comment, and their key in its mentions, so they hear of it.
  Collaboration guide, "Comments".
- A shared document's changes are events of its room, for agents
  (`wait_for_events`) and LiveViews (`Issho.Live.subscribe/3`):
  `"text.block_added"`, `"text.block_removed"` and `"text.changed"`, with
  the block's id, type and number (`Kotoba.Issho.events/2`).
  `Kotoba.Issho.document/1` gives them; `events: false` turns them off.
  Collaboration guide, "Events".
- `Kotoba.Live.stream_resume/5`: a suggestion that starts in the middle of
  its stream, with the text so far, for an answer that goes on in the
  app's process while the person is on another page. `stream_start/4` and
  `stream_resume/5` take `:block`, the block the text goes after (its
  number, or its id in a shared document); `kotoba:assist` has the
  request's `"place"`, and `kotoba:suggestion` has `"gone" => true` when
  the editor went away. The Suggestions guide's recipe, "A stream that
  outlives the page", keeps the answer in a GenServer and resumes it.
- `Kotoba.Issho.suggestions/4`: Issho's streams (Issho 0.4,
  `Issho.Streams`) as suggestions in a LiveView's shared editors, at the
  block of their place, picked up where they got to when the page comes
  back, and closed on Accept, Reject or Stop. Agents suggest text with
  `suggest_text` (`Kotoba.Issho.tools/0`).

- Inline suggestions: `Kotoba.Live.stream_start/4` with `display: :inline`
  streams the suggestion in the text, where it goes (after the caret,
  after the selection it replaces, or in a block below), tinted, with its
  status and buttons under it. As in the panel, it is not in the saved
  document, the undo history or a shared document until the person
  accepts it, as one undo step. Suggestions guide.

- An insert menu: a prompt with `insert: :command`
  (`{"/", :insert, insert: :command}`) opens on `/` a menu of what the
  field can insert or turn the block into, filtered as the person types:
  the built-in items of its features (`Kotoba.Prompts.commands/1`), the
  extensions' blocks and insert items (`insert` of an extension), and the
  app's own (a node, text, or a command), in the app's order and groups.
  An item runs as one undo step; in a block with text it goes below
  (`with_text: :below`) or turns the block (`:turn_into`). The `+` of the
  block handles opens it. Items have `:group` and `:keywords`, and an
  item with `:assist` asks the app for a suggestion (`/summarize`), which
  streams into the suggestion panel. Prompts guide, "The insert menu".
- Block handles, the `blocks` feature (off unless a field lists it):
  a grip beside each block drags it to another place, and opens its
  menu (Turn into, Duplicate, Delete, Copy a link to the block); a `+`
  adds a paragraph below it. `Alt+Shift+Up` and `Alt+Shift+Down` move
  the block at the caret, and `Cmd/Ctrl+/` opens its menu. Each change
  is one undo step, and a move in a shared editor is a move of the
  block. An extension's `blocks` put its nodes in Turn into
  (Extensions guide).
- `move_block`, an agent's tool (`Kotoba.Issho.tools/0`): moves a block
  after another one, as a block handle does.

### Fixed

- The first change after a document loads can be undone, also when no
  click or caret move came before it.

## [0.7.0] - 2026-10-22

On Issho 0.3: agents move with Issho's motion, and following is the room's.

### Changed (breaking)

- Requires `{:issho, "~> 0.3"}`.
- A shared editor joins with `issho`, the keys of every component
  (`Issho.Join`: `:instance`, `:document`, `:can`, `:people`, `:follow`,
  `:on_behalf_of`, `:claims`) and Kotoba's own (`:undo`, `:socket`,
  `:max_channels`), and `user`: `<.kotoba issho={[instance: MyApp.Issho,
  document: id]} user={@user}>`. `collab` and `Kotoba.Collab.token` are
  removed; `collab` raises with what to write instead. An unknown key
  raises.
- The server's functions are `Kotoba.Issho`'s, as Hakushi's and Masu's:
  `Kotoba.Issho.document/1` and `Kotoba.Issho.change/4`
  (`Kotoba.Collab.document` and `transact/4` are deprecated). A
  change's `:author` is a key or the app's actor.
- An agent moves with `Issho.Motion`: it goes to where it works and
  selects as a drag does only when someone of the room sees it, within a
  tool call's time budget; Issho's `travel: false` turns it off for every
  component, Kotoba's own `travel: false` for the editor's agents.

### Added

- A person's place (their selection) has a documented format, part of
  the API (`Kotoba.Issho.Place`, the Collaboration guide's "A person's
  place").
- The editor takes the app's user as its `Issho.Actor`
  says them (its key, name and colour), so a person is one person in the
  editor, a Hakushi canvas and Issho's lists. A person with no colour gets
  Issho's palette colour rather than one blue for everyone.
- An embed in Markdown is what the app renders between two comments that
  say what it is (`<!-- kotoba:embed {...} -->`, `<!-- /kotoba:embed -->`),
  which Markdown viewers leave out; `Kotoba.Content.from_markdown/2`
  reads it back as the embed, of any kind (a grid's table, a canvas's
  diagram), and the app's reader may say another, or `false` for the
  content.
- A pointer over an embed is no caret of the text, and the editor keeps
  the one followed on the screen unless Issho's pointers of its own room
  do (a page's pointers of another room do not).
- Embeds: your app's live things in the document, a canvas or a grid,
  which people use in place and take full screen (the `embeds` feature,
  `Kotoba.Nodes.Embed`, see the [Embeds](guides/embeds.md) guide). The
  document keeps an embed's `kind`, `ref` and `title`; the editor's
  `kotoba_embeds/1` (`Kotoba.Embeds`) renders your `:embed` slot for each
  one and puts it in its place with a LiveView portal, so that it is your
  LiveView's own content (its events, its LiveComponents), and stays as
  people type around it. An editor has embeds with `embeds`, and each
  editor chooses what it embeds.
- A link to something the app embeds becomes the embed: pasted alone on a
  line, or dropped on the editor, a URL goes to `kotoba_embeds/1`'s
  `resolve` (`fn url -> embed | nil end`), and becomes the canvas it
  links to; any other URL stays a link.
- An embeds picker of your options (`kotoba_embed_option/1`), opened from
  a toolbar button of your naming (`label="Canvas"`, `icon="canvas"`), and
  `Kotoba.Live.insert_embed/4`.
- An embed full screen and back (`embed.toggle_full`): the same content,
  in a layer over the page; Escape comes back.
- Keys in an embed are the embed's; Backspace after an embed deletes it,
  as after a horizontal rule, and undo brings it back.
- How an embed renders is the app's: the `:embed` option of
  `Kotoba.Renderer` and of `kotoba_content/1`, or `config :kotoba, embed:`
  (a canvas as its Mermaid diagram in Markdown, its picture in HTML). And
  back: `Kotoba.Content.from_markdown/2`'s `:embed` reader, or
  `config :kotoba, embed_from_markdown:` (for the Markdown paste too),
  makes a fenced block an embed again.
- `show_toolbar={false}`: an editor with no toolbar, with `readonly` a
  page that reads the document, its embeds live in it.
- `--kotoba-embed-height`, `--kotoba-embed-radius` and
  `--kotoba-embed-layer`.

- Following someone, from the editor's people list or the page's
  (`Issho.Components.pointers/1`, `Issho.Components.people/1`): the
  editor follows them to their caret. On an Issho page the page scrolls to
  them; an editor alone in its room scrolls to their caret itself. Going
  one's own way in the editor (a key, a click, a scroll) stops following.
  An editor that lists its people says whom it follows: "Following Ada",
  with Stop, in their colour, and a ring of it around the editor
  (`.kotoba-collab-following`, `data-collab-following`,
  `--collab-follow-color`), in Issho's look of following, the same on
  every block of the page (restyled with Issho's
  `--issho-following-background`, `--issho-following-text` and
  `--issho-following-ring`).
- `follow: false`: an editor that takes no part
  in following, though its room's other blocks do.
- The person's motion, as the app says it (Issho's `data-issho-motion`):
  carets glide and selections sweep only for a person who wants motion.

- An agent moves as a person does, so that the people can follow it: its
  caret goes to where it works, it selects text as a drag does, holds a
  moment on what it is about to format, link, replace or delete, and types
  at a person's pace; `add_block` adds an empty block and types its text
  in it. Only where it goes is sent (where it presses, where it lets go);
  each browser draws the way. Options: `config :kotoba, Kotoba.Issho,
  pace: 25, travel: true` (`pace: 0, travel: false` for changes that
  appear at once).
- Others' carets glide from place to place in the editor, longer the
  farther they go (up to 400ms; `--collab-caret-glide` for a fixed time),
  and a selection made from a caret sweeps from its start to its end
  (`--collab-sweep`, 350ms). None of it with reduced motion.
- An agent's page pointer (`Issho.Components.pointers/1`) goes to its
  caret, and follows it.
- A person's page pointer over the text is a place of it (Issho's
  `point`): each page draws it on the same word, however the text wraps
  there.

### Fixed

- A click in an embed's content (a grid's cell, a canvas's field) selects
  no embed, only a click on its edge does: the next click in the text puts
  the caret there, where the embed selected took it away.
- A caret or a pointer at a place between blocks (the start of the
  document, before an embed) is at the top of the block there, a line
  high, rather than as high as the editor: a page pointer there was at
  the bottom of the editor, off the screen.

## [0.6.0] - 2026-10-21

Collaboration runs on [Issho](https://hex.pm/packages/issho): the same
editor, document model, merge rules, offline drafts and form flow, with
Issho as the document's authority, the room's people and their cursors.
A page of Kotoba and other Issho components shares one connection. Why,
what it gives a page, and the steps: the
[Upgrading to 0.6](guides/upgrading.md) guide.

### Added

- Agents in shared documents: `Kotoba.Issho.tools/0`, tools an agent
  uses as a person uses the editor, however it reaches the app (its own
  model through an API with Issho's `Issho.Tools`, or MCP with
  `Issho.MCP`): read the blocks, select text (the
  people see its selection, in its colour), type (they see it written, a
  few characters at a time), replace, delete, format, link, add blocks,
  copy and paste, between the documents of a room too. Its changes are
  the editor's operations, and merge with everyone's.

### Changed

- **Breaking:** collaboration needs `{:issho, "~> 0.2"}`. To upgrade:
  - replace `{Kotoba.Collab.Supervisor, name:, store:, policy:}` with an
    `{Issho, name: MyApp.Issho, pubsub:, endpoint:, policy: MyApp.Collaboration}`
    child, whose policy's `document/2` returns
    `Kotoba.Collab.document(store: ..., policy: ...)`;
  - move your channel's `authorize/3` into the policy's
    `authorize(identity, document_id, action)` (`identity.key` is the
    user's id; actions are `:join`, `:read`, `:write` and `:lock`);
  - replace `use Kotoba.Collab.Channel` with `use Issho.Channel` and the
    socket's `channel "kotoba:*"` with `channel "issho:*"`, at
    `/issho/socket` (or pass `:socket` to `token/3`);
  - call `Kotoba.Collab.token`, `content/2,3` and `transact/4` with the
    Issho instance (`MyApp.Issho`) in place of the LiveView socket or the
    supervisor;
  - add `on_mount Issho.Live` to the LiveViews of shared editors, and
    remove your `handle_event("kotoba:collab_token", ...)`: Issho renews
    the credentials it granted, asking your policy again;
  - map `issho` in an import map, next to `kotoba/collab`.

  `Kotoba.Collab.Store` is unchanged, and documents it saved before open
  as they are, with their history, and are saved in Issho's form with
  their next change.
- `Kotoba.Collab.content/2` gives `{:ok, %{"epoch", "revision", "content"}}`
  with the content as a `Kotoba.Content`.
- Two editors of one document on a page share its channel.
- The editors of a page whose documents share an Issho room
  (`"notebook:7/cell-1"`, `"notebook:7/cell-2"`: the part before the
  `"/"`) share one connection and the room's people, and a person's
  cursor goes from one editor to the other. `Kotoba.Collab.token`
  signs for the room and says it in the credentials' `"room"`; the
  policy's `authorize/3` is asked about the room.
- Undo in shared editors is the app's choice (`Kotoba.Collab.token`'s
  `:undo`): the editor's own steps (`:editor`, as before), the page's
  (`:page`, Issho's `pageHistory`: the person's last change in whichever
  editor or component they made it, which takes the focus), or none
  (`false`).
- `Kotoba.Collab.token` takes `people: false` for a page that lists the
  room's people once, with Issho's `Issho.Components.people/1`: the
  editors then list and announce no one.

### Fixed

- A collaborator's caret on an empty line shows, at the line's start.

### Removed

- `Kotoba.Collab.Supervisor`, `Kotoba.Collab.Channel`,
  `Kotoba.Collab.DocServer`, and the transaction functions of
  `Kotoba.Collab.Document` (`commit/4`, `at_revision/4`, `snapshot/1`):
  Issho orders transactions and keeps their receipts and journal.

## [0.5.0] - 2026-10-20

Attachment captions, and two fixes to rendered HTML.

### Added

- Attachments have a caption: the optional `caption` field of
  `Kotoba.Nodes.Attachment` (JSON key `caption`, written only when set)
  and of the editor's attachment node. An image's caption is its `alt`
  text and its `figcaption`; a PDF's, a video's or another file's is the
  text of its download link and the name of its viewer or player. Plain
  text and Markdown (`![caption](url)`) use it too, and so does the
  `:untrusted` policy. With no caption, the file name shows, as before.
  `Kotoba.Nodes.Attachment.label/1` returns the caption, else the name.
- The editor has a caption field under the selected attachment: a click
  or Alt+F10 goes to it, Enter keeps the caption, Escape leaves it as it
  was. Keeping a caption is one undo step, and a shared editor sends it
  to the others.
- `Kotoba.Content.from_markdown/2` with `:attachments` makes the alt text
  of `![The timeline of the project](attachment:timeline)` the
  attachment's caption, unless it is empty or the file name. A caption
  the attachment has already wins.
  ([#49](https://github.com/hattoriai/kotoba/pull/49))

### Fixed

- A nested list in rendered HTML no longer shows a second marker: the
  item that holds it, which has no text of its own, has the
  `kotoba-li-nested` class, as in the editor.
  ([#48](https://github.com/hattoriai/kotoba/pull/48))
- `kotoba.css` sizes a rendered image attachment: its `img` is no wider
  than the text and keeps its proportions, with the radius of the
  editor's images, and its `figcaption` is small and muted. A large
  screenshot rendered at its natural width and overflowed the column.
  ([#49](https://github.com/hattoriai/kotoba/pull/49))

## [0.4.0] - 2026-10-20

Attachments of files on the server, underline and highlight in Markdown,
one collaboration socket for the shared editors of a page, and stable
collaborator cursors. This release has a breaking change, listed under
Changed.

### Added

- `Kotoba.Attachments.store/2` makes an attachment of a file on the
  server, as an upload does: it checks the file, stores it, and deletes it
  again when the storage's result makes no valid attachment. For seeds,
  imports, and files an app makes itself. `Kotoba.Live.consume_uploads/4`
  stores uploads with it.
- The `:attachments` option of `Kotoba.Content.from_markdown/2`: a
  paragraph of only `![alt](attachment:name)` images becomes the
  attachment of that name, or a gallery of several.

### Changed

- Underline and highlight have Markdown: `Kotoba.Renderer.to_markdown/2`
  writes `__underline__` and `==highlight==`, and
  `Kotoba.Content.from_markdown/2` reads them back. They were dropped
  before, so a document turned into Markdown and back (an AI translation,
  say) lost them. Text colors and the color of a highlight still have no
  Markdown.
  ([#47](https://github.com/hattoriai/kotoba/pull/47))
- **Breaking:** `__text__` read from Markdown is an underline, not bold.
  Kotoba writes bold as `**text**`.
- The warning of an upload's preview that fails names "the file" rather
  than "the upload".
- The shared editors of a page share one collaboration socket, each with
  its own channel, instead of opening a socket each: a page of 20 shared
  editors opens one WebSocket, not 20. A missed revision or removing an
  editor affects that editor's channel only, and so does a push timeout
  unless a ping finds the connection dead, which reconnects the socket
  once for all its editors. A socket takes up to `Kotoba.Collab.token`'s
  new `:max_channels` editors, 100 by default; pass a lower
  `:max_channels_per_transport` of the socket there.
  ([#38](https://github.com/hattoriai/kotoba/issues/38))

### Fixed

- Collaborator cursors keep their last known position when awareness arrives
  before the referenced characters or paragraph, then follow the new position
  once the document catches up.
  ([#44](https://github.com/hattoriai/kotoba/pull/44))

## [0.3.0] - 2026-10-17

Full Markdown. This release has breaking changes, listed under Changed.

### Added

- `Kotoba.Content.from_markdown/2` reads CommonMark and GitHub Flavored
  Markdown with MDEx (comrak, a port of GitHub's cmark-gfm): setext
  headings, `__` emphasis, nested emphasis, entities and escapes,
  reference links, link titles, autolinks, images, `+` bullets and `1)`
  lists, nested lists and check lists, lazy lines, `~~~` and indented code,
  tables with column alignment, and footnotes. Every example of the GFM
  spec (CommonMark included) reads into Kotoba and writes back to Markdown
  that renders the same, but for raw HTML, which is text, and list items
  that hold blocks (see below); a test runs them all.
- `from_markdown/2` takes `features:`: a construct whose feature is off
  becomes its closest form, with no text lost.
- **Pasted Markdown** becomes rich text: plain text that reads as Markdown
  (and no rich HTML) goes to the server, which reads it as
  `from_markdown/2` does, with the editor's features. `<.kotoba>` renders
  the server's half itself (`Kotoba.MarkdownPaste`, a LiveComponent): an
  app adds no code. `paste_markdown={false}` turns it off.
- **Quotes that hold blocks**: paragraphs, lists, code, tables and other
  quotes, with Lexical's own `shadowRoot` opt-in on the quote node.
- **Images from a URL** (`image` node, the `images` feature): Markdown's
  `![alt](url "title")`, in the text. The URL is checked as a link's is,
  and the `:untrusted` policy renders the alternative text.
- **Footnotes** (`footnotereference` and `footnotedefinition` nodes, the
  `footnotes` feature), numbered in the order of their first reference,
  in a list at the end of the rendered HTML.
- **Blank lines**: the empty paragraphs that a person types between
  blocks keep their height in HTML (`<p><br></p>`) and are `&nbsp;` in
  Markdown, which reads back. The `blank_lines: :collapse` render option
  and `<.kotoba blank_lines={:collapse}>` leave them out.
- Table columns keep their alignment (`kotoba-align-*` classes, `:-:` in
  Markdown).

### Changed

- **Breaking:** MDEx is a dependency: a native library, precompiled for
  Linux (glibc 2.35 or later, and musl), macOS, Windows and FreeBSD; on
  another system it builds with Rust.
- **Breaking:** the lines of a Markdown paragraph are one line, as
  CommonMark has them (a line ending with two spaces or `\` is a line
  break). The old reader made each line a line break.
- **Breaking:** a quote read from Markdown is a quote of blocks:
  `<blockquote><p>...</p></blockquote>`.
- **Breaking:** `image`, `footnotereference` and `footnotedefinition` are
  built-in node types: an app node cannot have them.
- **Breaking:** `h5` and `h6` render as themselves (they were `h4`).
- The Markdown of `Kotoba.Renderer.to_markdown/2` nests formats (a format
  opens once over the text that has it), keeps a URL with spaces or
  parentheses in angle brackets, and gives two lists in a row different
  markers, so that it reads back as the same document.
- `Kotoba.Features` has `images` and `footnotes`. An editor with a
  `features` list has them only when the list names them.
- A list item with several paragraphs, or with a code block, a quote or a
  table, reads as an item with line breaks and the blocks after the list:
  a Lexical list item holds inline content only.

### Security

- The lock file of the repository has bandit 1.13.1 (for CVE-2026-105659
  and CVE-2026-105660) and decimal 3.2.0 (for CVE-2026-97853). The Hex
  package does not have the lock file: an app gets these fixes with
  `mix deps.update bandit decimal`. Bandit is for the development server
  of Kotoba only. Kotoba does not call `Decimal.round/3`.

## [0.2.2] - 2026-10-17

### Changed

- Kotoba supports Phoenix 1.7 and Phoenix LiveView 1.1 (it needed Phoenix
  1.8 and LiveView 1.2): it requires `~> 1.7.14 or ~> 1.8` and `~> 1.1`.
  Nothing changes for an app on the newer versions. The floor job of CI
  runs the tests on Elixir 1.18 with Phoenix 1.7 and LiveView 1.1.

### Fixed

- A colleague's edit in a shared editor no longer takes the focus and the
  caret from another editor of the page, so what the author types next is
  no longer lost: an editor without focus restores its selection in the
  model only.

## [0.2.1] - 2026-10-08

### Fixed

- A text format button (Bold, Italic, Underline, Strikethrough, Inline
  code, Subscript, Superscript, Highlight without the palette), in the
  toolbar or the selection menu, takes the format off text that has it,
  instead of applying it again; at the caret, it turns the format off for
  the next text. The color palette at a caret in colored text shows its
  colors. ([#36](https://github.com/hattoriai/kotoba/issues/36))

## [0.2.0] - 2026-10-02

### Added

- A selection menu: `<.kotoba selection_menu>` shows a menu over the
  selected text, with the default commands (bold, italic, underline,
  strikethrough, inline code, highlight, link) or the commands of a list;
  `<:selection>` with the new `kotoba_selection_menu/1` gives the app's own
  buttons. Alt+F10 focuses it and Escape closes it. It is themed with the
  new `--kotoba-floating-*` properties (also in `kotoba-sumi.css`).
- A link card: with the caret in a link, a card shows the URL (it opens in
  a new tab) and Edit link and Remove link buttons. Cmd/Ctrl+click opens a
  link of the editor.
- `Kotoba.Content.from_markdown/2` reads quotes, check lists, horizontal
  rules, pipe tables, `*italic*`, `~~strikethrough~~` and `***both***`,
  nested formats (a link in bold), and the first number of a numbered
  list: Kotoba's own Markdown now reads back.
- A readable baseline for `<.kotoba_content>` (headings, paragraphs,
  lists, quotes, links, code), with the weight of one class so that an
  element reset such as `a { color: inherit }` does not undo it, and
  `highlightRenderedContent()` to color rendered code blocks with the
  editor's grammars.

- Optional collaboration: shared documents with participant cursors,
  read-only viewers, per-author undo and redo, local draft recovery after
  reconnect or reload, and form submission of an accepted server revision.
  See the [Collaboration guide](guides/collaboration.md) for setup and storage.
- PDF and video previews (#6, #7). A PDF shows in the browser's viewer (an
  `object` with a download link for a browser that has none), in the
  editor and in the rendered HTML. MP4 and WebM videos are checked from
  their bytes (`video/mp4`, `video/webm`; QuickTime, Matroska and audio-only
  files stay `application/octet-stream`), served inline, and play in a
  `video` with controls, `preload="metadata"` and no autoplay; in the
  editor, a video that does not load shows as a file. An attachment's new
  `preview` (a PDF's first page, a video's poster) comes from the
  `:preview` option of `Kotoba.Live.consume_uploads/4`, and must be a safe
  URL. `Kotoba.Storage.Local.Plug` answers `Range` requests (`206`,
  `416`), which video seeking needs. `Kotoba.Nodes.Attachment.pdf?/1` and
  `video?/1` are new.
- Image galleries (#5): a `gallery` node (`Kotoba.Nodes.Gallery`, part of
  the `attachments` feature, valid only under the root) that holds
  attachments, rendered as a `div.kotoba-gallery` grid. Images uploaded
  together make a gallery, each in the place of its own marker (the order
  stays when uploads finish in another order); an image uploaded with an
  image of a gallery selected joins it. The arrow keys move between the
  images and out of the gallery, `Alt+Left` and `Alt+Right` move an
  image, Backspace and Delete remove one, and the live region says the
  position ("2 of 3: cat.png"). The toolbar's Image group (`gallery`,
  `image-previous`, `image-next`) shows while an image is selected: it
  groups the image with the images next to it, ungroups a gallery, and
  moves an image. A gallery of one image becomes that image.
- Suggestions (#26): text that the server streams into the editor, for
  example the answer of a language model. `Kotoba.Live.stream_start/4`
  (`at: :selection | :caret | :after | :end`, `format: :markdown | :text`,
  `label`), `stream_chunk/4`, `stream_end/3`, `stream_cancel/3` and
  `stream_ref/0`. The text shows in a panel as it streams, rendered from
  the whole text at each chunk (a Markdown format cut by a chunk is never
  half a format), with only the editor's features; Accept
  (`Cmd/Ctrl+Enter`) inserts it as one undo step, Reject (Escape) leaves
  the document and the selection as they were, and Stop keeps what has
  come. The `assist` attribute gives the toolbar an Assist menu of the
  app's actions: an action pushes `kotoba:assist` (`ref`, `action`, the
  selected text), and the editor pushes `kotoba:suggestion` (`accept`,
  `reject`, `stop`). Extensions ask with `context.assist/2`. The dev
  server has a fake model, and the Suggestions guide streams Claude with
  Req.
- Guides: Editing features (every feature, its toolbar button, keyboard
  and Markdown shortcuts, colors, links, code blocks, tables and custom
  toolbars) and Rendering (the HTML of each node, styling, HTML/text/
  Markdown outside a page, content without the editor). The quickstart
  has a complete LiveView, and the README a feature overview.
- Richer prompts (#8). A prompt is a callback, or options: `spaces: true`
  (queries with spaces, "Ada Lovelace", ended by two spaces),
  `min_length`, `max_length` (up to 200), `items:` (a local list that the
  editor filters, with no request), `insert: :text` or
  `insert: {:node, type}` (text or a node of the app, from the item's
  `:text` and `:attrs`), and `async: true` (the search runs in
  `start_async`; `Kotoba.Live.handle_prompt_async/3` pushes its result).
  The menu says "Keep typing to search", "Searching…" and "Results did
  not load" (a search that failed, with `error: true` in the reply, or
  that had no answer after 8 seconds), keeps the answers of its queries,
  and drops an answer to an older query. `Kotoba.Prompts.search/3`,
  `config/1`, `specs/1`, `find_spec/2` and `filter/2` are new.
- A color palette (#4): the Highlight button opens a palette of text
  colors and highlights (red, orange, yellow, green, blue, purple, gray)
  and "Remove color", from the mouse and the keyboard. A color is stored
  as a name in the text node's `style`
  (`color: var(--kotoba-color-red)`), and renders as a class
  (`span.kotoba-color-red`, `mark.kotoba-highlight-green`); any other
  style is dropped in the editor and never rendered.
  `Kotoba.Nodes.Text.colors/1` reads them. The highlight format with no
  color stays the default yellow highlight, so existing documents render
  as before. A text color is part of the `highlight` feature.
- Underline, highlight, subscript and superscript are features, with
  their keyboard shortcuts (`Cmd/Ctrl+U`, `Cmd/Ctrl+Shift+H`,
  `Cmd/Ctrl+,`, `Cmd/Ctrl+.`) and toolbar commands. The default toolbar
  has Underline and Highlight; an app's toolbar can have Subscript and
  Superscript. The `==` Markdown shortcut highlights only in an editor
  with `highlight`. Highlighted text has its own colour,
  `--kotoba-highlight` (a light yellow), not the selection's.

- Features: `<.kotoba features={~w(bold italic links lists)}>` gives an
  editor only those built-in features (`Kotoba.Features`: bold, italic,
  underline, strikethrough, highlight, subscript, superscript,
  inline_code, links, headings, quotes, lists, check_lists,
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

- An empty table cell keeps the height of a line, in the editor and in the
  rendered HTML; it showed as a thin strip.
- `Kotoba.Live.consume_uploads/4` consumes an entry once. LiveView drops
  a consumed entry a message later, so a second call before that (the
  next file done, a form change) consumed it again and crashed the
  LiveView: of several files that finished one after the other, only the
  first was stored.

- A rendered check list (`ul.kotoba-check`) shows a box, checked or not,
  in front of each item, as the editor does; before, `kotoba.css` hid the
  bullets and drew no box.
- The case formats (`lowercase`, `uppercase`, `capitalize`) show in the
  editor and in rendered content (`span.kotoba-uppercase`...).
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

[Unreleased]: https://github.com/hattoriai/kotoba/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/hattoriai/kotoba/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/hattoriai/kotoba/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/hattoriai/kotoba/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/hattoriai/kotoba/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/hattoriai/kotoba/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/hattoriai/kotoba/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/hattoriai/kotoba/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/hattoriai/kotoba/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/hattoriai/kotoba/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/hattoriai/kotoba/releases/tag/v0.1.0
