// Suggestions: text that the server streams into the editor, for example
// the answer of a language model to "Rewrite this".
//
// The server starts a stream (`kotoba:stream` with `op: "start"`), sends
// its text in chunks and ends it (`Kotoba.Live.stream_start/4`,
// `stream_chunk/4`, `stream_end/3`, `stream_cancel/3`). The text is not in
// the document while it streams: it shows in a panel under the editable
// area, rendered by a read-only editor with the same nodes, from the whole
// text at each chunk. So Markdown that a chunk cuts in two (`**bo`) is
// never half a format in the document. When the stream ends, the person
// accepts the suggestion (the Accept button, or Cmd/Ctrl+Enter in the
// editor), which inserts it in one update (one undo step), or rejects it
// (Reject, or Escape), which leaves the document as it was.
//
// Where the text goes (`at`): in place of the selection ("selection", the
// default), at the caret ("caret"), after the block of the selection
// ("after"), or at the end of the document ("end"). The selection is kept
// from when the suggestion was asked for (the Assist menu) or started, so
// the person can go on editing meanwhile. When that selection is no longer
// in the document, the text goes at the end.
//
// How it shows (`display`): in the panel ("panel", the default), or in the
// text ("inline"), where it goes: after the caret, after the selection it
// replaces (struck, where the browser has CSS highlights), or as a block
// below. Inline, the suggestion is a pending node (see nodes/internal.ts):
// not in the saved document, not shared, and not in the undo history (its
// updates are historic). An undo or a remote change that takes it away puts
// it back; the person deleting it (typing over it) rejects the suggestion.
// The panel then holds only the suggestion's status and buttons, under it.
// A caret in the middle of a word shows it below the block: the text node
// is not split, so the document does not change.
//
// A stream can start with text (`Kotoba.Live.stream_resume/5`: a stream
// that the app went on with while the person was on another page), and at
// a block the server names (`block`: its number, 1 for the first, or its
// id in a shared document): the text goes after it, or at its end. A block
// that is not found gives the end of the document, as a lost selection
// does. A request (`kotoba:assist`) says its block in `place`, so that the
// app can keep it for a return. When the editor goes (the person leaves
// the page), it says `stop` with `gone: true`.
//
// Markdown is read with the editor's own Markdown shortcuts, so a
// suggestion has only the formats and blocks of the editor's features.
//
// With `data-assist`, the toolbar's Assist button opens a menu of the app's
// actions. An action pushes `kotoba:assist` with a new `ref`, the action
// and the selected text; the app answers with a stream of that `ref`. The
// editor then pushes `kotoba:suggestion` when the person accepts, rejects
// or stops the suggestion, so that the app can stop its work.

import { $generateNodesFromMarkdownString, type Transformer } from "@lexical/markdown";
import { $findMatchingParent } from "@lexical/utils";
import {
  $createLineBreakNode,
  $createParagraphNode,
  $createTextNode,
  $createRangeSelection,
  $getNodeByKey,
  $getRoot,
  $getSelection,
  $isElementNode,
  $isRangeSelection,
  $isRootNode,
  $isRootOrShadowRoot,
  $isTextNode,
  $setSelection,
  COMMAND_PRIORITY_HIGH,
  CONTROL_OR_META,
  HISTORIC_TAG,
  HISTORY_PUSH_TAG,
  KEY_DOWN_COMMAND,
  KEY_ESCAPE_COMMAND,
  isExactShortcutMatch,
  mergeRegister,
  type EditorState,
  type Klass,
  type LexicalEditor,
  type LexicalNode,
  type RangeSelection,
} from "lexical";

import { createKotobaEditor } from "./editor";
import { $domSelection } from "./link";
import { $createPendingNode, $isPendingNode, setPendingContent, type PendingNode } from "./nodes/internal";
import { placeOver } from "./selection_menu";

export type SuggestionTarget = "selection" | "caret" | "after" | "end";
export type SuggestionFormat = "markdown" | "text";
export type SuggestionDisplay = "panel" | "inline";

/** An action of the Assist menu. */
export interface AssistAction {
  id: string;
  label: string;
}

export interface StreamStart {
  at?: unknown;
  format?: unknown;
  label?: unknown;
  display?: unknown;
  /** The text so far, of a stream that resumes. */
  text?: unknown;
  /** The block it goes after (its number, or its id in a shared document). */
  block?: unknown;
  /** In a shared document: the selection it replaces (`Kotoba.Issho.Place`). */
  selection?: unknown;
}

export interface Suggestions {
  /** Asks the app for a suggestion (`kotoba:assist`). Returns its ref, or `null` when the editor has no assist. */
  request(action: string, detail?: Record<string, unknown>): string | null;
  /** Opens the Assist menu of the toolbar button. */
  openMenu(button: HTMLElement): void;
  start(ref: string, options: StreamStart): void;
  chunk(ref: string, text: string): void;
  end(ref: string): void;
  cancel(ref: string): void;
  /** Discards the open suggestion (a new document from the server). */
  discard(): void;
  dispose(): void;
}

interface SuggestionOptions {
  host: HTMLElement;
  namespace: string;
  /** The node classes of the editor, for the preview. */
  nodes: readonly Klass<LexicalNode>[];
  builtInNodes: readonly Klass<LexicalNode>[];
  /** The Markdown shortcuts of the editor: the formats and blocks that a suggestion can have. */
  transformers: readonly Transformer[];
  /** The Assist menu's actions; empty for an editor with no assist. */
  actions: readonly AssistAction[];
  /** Pushes an event to the app; `null` for an editor with no assist, which pushes nothing. */
  push: ((event: string, payload: Record<string, unknown>) => void) | null;
  announce(message: string): void;
  /** In a shared editor: the node of a shared id, and the shared id of a node. */
  keyOf?(id: string): string | null;
  idOf?(key: string): string | null;
  /** In a shared editor: a range as a shared selection, and back (in a read). */
  sharedOf?(range: RangeSelection): unknown;
  rangeOf?(shared: unknown): { anchor: Point; focus: Point } | null;
}

interface Point {
  key: string;
  offset: number;
  type: "text" | "element";
}

type State = "streaming" | "done" | "stopped";

interface Active {
  ref: string;
  at: SuggestionTarget;
  format: SuggestionFormat;
  display: SuggestionDisplay;
  target: RangeSelection | null;
  text: string;
  state: State;
}

/** With no chunk for this long, a stream counts as stopped. */
export const STREAM_IDLE_TIMEOUT = 30_000;

const TARGETS = new Set<string>(["selection", "caret", "after", "end"]);

const readTarget = (value: unknown): SuggestionTarget =>
  typeof value === "string" && TARGETS.has(value) ? (value as SuggestionTarget) : "selection";

const readFormat = (value: unknown): SuggestionFormat => (value === "text" ? "text" : "markdown");

const readDisplay = (value: unknown): SuggestionDisplay => (value === "inline" ? "inline" : "panel");

/** The updates of a pending suggestion: not in the undo history, and not the person's. */
const PENDING_TAG = "kotoba-pending";
const PENDING_TAGS = [HISTORIC_TAG, PENDING_TAG];

/** The CSS highlight of the text that an inline suggestion replaces. */
const REPLACED = "kotoba-replaced";

let refs = 0;
const newRef = (): string => {
  refs += 1;
  const random = Math.random().toString(36).slice(2, 10);
  return `s${refs}-${random}`;
};

/** Plain text as paragraphs: a blank line starts a paragraph, a line break is a line break. */
function $textNodes(text: string): LexicalNode[] {
  return text
    .split(/\n{2,}/)
    .filter((part) => part !== "")
    .map((part) => {
      const paragraph = $createParagraphNode();
      part.split("\n").forEach((line, index) => {
        if (index > 0) paragraph.append($createLineBreakNode());
        if (line !== "") paragraph.append($createTextNode(line));
      });
      return paragraph;
    });
}

// A kept selection is valid when both points are in the document and in
// range (the person may have edited the text meanwhile).
function $isValid(selection: RangeSelection): boolean {
  return [selection.anchor, selection.focus].every((point) => {
    const node = $getNodeByKey(point.key);
    if (node === null || !node.isAttached()) return false;
    if (point.type === "text") return $isTextNode(node) && point.offset <= node.getTextContentSize();
    return $isElementNode(node) && point.offset <= node.getChildrenSize();
  });
}

/**
 * A selection that ends at the very start of a later block (a triple
 * click selects a paragraph to the start of the next) ends at the end of
 * the block before: what it replaces is the words selected, not the break
 * after them.
 */
function $trimmed(target: RangeSelection): RangeSelection {
  const range = target.clone();
  const end = range.isBackward() ? range.anchor : range.focus;
  const start = range.isBackward() ? range.focus : range.anchor;
  if (range.isCollapsed() || end.offset !== 0) return range;
  const endBlock = $topBlock(end.getNode());
  const startBlock = $topBlock(start.getNode());
  if (endBlock === null || startBlock === null || endBlock.is(startBlock)) return range;
  const first = $isElementNode(endBlock) ? endBlock.getFirstDescendant() : endBlock;
  if (first !== null && !first.is(end.getNode()) && !endBlock.is(end.getNode())) return range;
  const previous = endBlock.getPreviousSibling();
  if (previous === null) return range;
  const last = $isElementNode(previous) ? previous.getLastDescendant() : previous;
  if ($isTextNode(last)) end.set(last.getKey(), last.getTextContentSize(), "text");
  else if ($isElementNode(previous)) end.set(previous.getKey(), previous.getChildrenSize(), "element");
  return range;
}

function $topBlock(node: LexicalNode): LexicalNode | null {
  if ($isRootOrShadowRoot(node)) return null;
  return $findMatchingParent(node, (candidate) => {
    const parent = candidate.getParent();
    return parent !== null && $isRootOrShadowRoot(parent);
  });
}

/**
 * Sets the selection where the suggestion goes. For "after" and "end", it
 * is in a new paragraph, which it returns so that an empty one can go.
 */
function $placeSelection(active: Active): { selection: RangeSelection; paragraph: LexicalNode | null } {
  const kept = active.target !== null && $isValid(active.target) ? active.target.clone() : null;

  if (kept === null || active.at === "after" || active.at === "end") {
    const root = $getRoot();
    const end = kept === null ? null : kept.isBackward() ? kept.anchor.getNode() : kept.focus.getNode();
    const block = kept === null || active.at === "end" || end === null ? root.getLastChild() : $topBlock(end);
    const paragraph = $createParagraphNode();
    if (block === null) root.append(paragraph);
    else block.insertAfter(paragraph);
    return { selection: paragraph.select(), paragraph };
  }

  if (active.at === "caret" && !kept.isCollapsed()) {
    const end = kept.isBackward() ? kept.anchor : kept.focus;
    kept.anchor.set(end.key, end.offset, end.type);
    kept.focus.set(end.key, end.offset, end.type);
  }
  $setSelection(kept);
  return { selection: kept, paragraph: null };
}

/** The pending nodes of the document. */
function $pendingNodes(node: LexicalNode = $getRoot()): PendingNode[] {
  if ($isPendingNode(node)) return [node];
  return $isElementNode(node) ? node.getChildren().flatMap((child) => $pendingNodes(child)) : [];
}

/**
 * Puts the pending node of an inline suggestion where its text goes: in the
 * line, at the caret or after the selection, when that is at the edge of a
 * text (no text node is split), else as a block below the block of the
 * selection, or at the end of the document.
 */
function $placePending(active: Active): PendingNode {
  const kept = active.target !== null && $isValid(active.target) ? active.target : null;
  const end = kept === null ? null : kept.isBackward() ? kept.anchor : kept.focus;

  if (end !== null && (active.at === "caret" || active.at === "selection")) {
    const node = end.getNode();
    const inline = $createPendingNode(active.ref, true);
    if (end.type === "text" && $isTextNode(node)) {
      if (end.offset === node.getTextContentSize()) return node.insertAfter(inline, false) as PendingNode;
      if (end.offset === 0) return node.insertBefore(inline, false) as PendingNode;
    } else if ($isElementNode(node) && !$isRootOrShadowRoot(node) && !node.isInline()) {
      const child = node.getChildAtIndex(end.offset);
      if (child === null) node.append(inline);
      else child.insertBefore(inline, false);
      return inline;
    }
  }

  const pending = $createPendingNode(active.ref, false);
  const block = end === null || active.at === "end" ? null : $topBlock(end.getNode());
  if (block === null) $getRoot().append(pending);
  else block.insertAfter(pending, false);
  return pending;
}

/**
 * Puts an inline suggestion's nodes in place of its pending node, after
 * removing the text it replaces.
 */
function $insertAtPending(active: Active, pending: PendingNode, nodes: LexicalNode[]): void {
  const kept = active.target;
  if (active.at === "selection" && kept !== null && !kept.isCollapsed() && $isValid(kept)) kept.clone().removeText();

  if (pending.isInline()) {
    const selection = pending.selectPrevious();
    pending.remove();
    if (nodes.length > 0) selection.insertNodes(nodes);
    return;
  }
  const paragraph = $createParagraphNode();
  pending.replace(paragraph);
  if (nodes.length === 0) {
    paragraph.remove();
    return;
  }
  paragraph.select().insertNodes(nodes);
  if (paragraph.isAttached() && paragraph.isEmpty()) paragraph.remove();
}

/** The DOM range of a kept selection of text, for the highlight of what it replaces. */
function domRange(editor: LexicalEditor, selection: RangeSelection): Range | null {
  const point = (key: string, offset: number): [Node, number] | null => {
    const element = editor.getElementByKey(key);
    if (element === null) return null;
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
    const text = walker.nextNode();
    return text === null ? null : [text, Math.min(offset, text.textContent?.length ?? 0)];
  };
  if (selection.anchor.type !== "text" || selection.focus.type !== "text") return null;
  const [first, last] = selection.isBackward() ? [selection.focus, selection.anchor] : [selection.anchor, selection.focus];
  const start = point(first.key, first.offset);
  const end = point(last.key, last.offset);
  if (start === null || end === null) return null;
  const range = document.createRange();
  range.setStart(...start);
  range.setEnd(...end);
  return range;
}

export function createSuggestions(editor: LexicalEditor, options: SuggestionOptions): Suggestions {
  const panel = document.createElement("div");
  panel.className = "kotoba-suggestion";
  panel.hidden = true;
  panel.setAttribute("role", "region");
  panel.setAttribute("aria-label", "Suggestion");

  const header = document.createElement("div");
  header.className = "kotoba-suggestion-header";
  const title = document.createElement("span");
  title.className = "kotoba-suggestion-title";
  const status = document.createElement("span");
  status.className = "kotoba-suggestion-status";
  header.append(title, status);

  const content = document.createElement("div");
  content.className = "kotoba-suggestion-content";

  const actions = document.createElement("div");
  actions.className = "kotoba-suggestion-actions";
  const button = (label: string, name: string): HTMLButtonElement => {
    const element = document.createElement("button");
    element.type = "button";
    element.className = `kotoba-suggestion-button kotoba-suggestion-${name}`;
    element.textContent = label;
    return element;
  };
  const accept = button("Accept", "accept");
  const reject = button("Reject", "reject");
  const stop = button("Stop", "stop");
  accept.title = "Accept (Ctrl+Enter)";
  reject.title = "Reject (Escape)";
  actions.append(accept, reject, stop);

  panel.append(header, content, actions);
  options.host.append(panel);

  // The preview: a read-only editor with the nodes of the editor.
  const preview = createKotobaEditor({
    namespace: `${options.namespace}-suggestion`,
    nodes: options.nodes,
    builtInNodes: options.builtInNodes,
    editable: false,
  });
  preview.setRootElement(content);
  const transformers = [...options.transformers];

  // Suggestions asked for with the Assist menu: ref → the kept selection and the target.
  const requested = new Map<string, { target: RangeSelection | null }>();
  let active: Active | null = null;
  let frame = 0;
  let idle: ReturnType<typeof setTimeout> | undefined;

  const $readSelection = (): RangeSelection | null => {
    const selection = $domSelection(editor) ?? $getSelection();
    return $isRangeSelection(selection) ? selection.clone() : null;
  };

  // In an update: the DOM selection makes a selection object.
  const readSelection = (): { target: RangeSelection | null; text: string } => {
    let result: { target: RangeSelection | null; text: string } = { target: null, text: "" };
    editor.update(
      () => {
        const target = $readSelection();
        result = { target, text: target?.getTextContent() ?? "" };
      },
      { discrete: true },
    );
    return result;
  };

  const $nodes = (text: string, format: SuggestionFormat): LexicalNode[] =>
    format === "text" ? $textNodes(text) : $generateNodesFromMarkdownString(text, transformers);

  const renderPreview = (): void => {
    frame = 0;
    const current = active;
    if (current === null) return;
    preview.update(
      () => {
        const root = $getRoot();
        root.clear();
        const nodes = $nodes(current.text, current.format);
        if (nodes.length > 0) root.append(...(nodes as never[]));
        else root.append($createParagraphNode());
      },
      { discrete: true },
    );
  };

  const schedulePreview = (): void => {
    if (frame === 0) frame = requestAnimationFrame(renderPreview);
  };

  // Inline: the suggestion's place in the text, and the text it replaces.
  let pendingKey: string | null = null;
  let replaced: Range | null = null;

  const highlights = (): Map<string, Highlight> | null =>
    typeof CSS !== "undefined" && "highlights" in CSS && typeof Highlight !== "undefined"
      ? (CSS.highlights as unknown as Map<string, Highlight>)
      : null;

  const setReplaced = (range: Range | null): void => {
    const registry = highlights();
    if (registry === null) return;
    let highlight = registry.get(REPLACED);
    if (highlight === undefined) {
      highlight = new Highlight();
      registry.set(REPLACED, highlight);
    }
    if (replaced !== null) highlight.delete(replaced);
    replaced = range;
    if (range !== null) highlight.add(range);
  };

  // The panel holds the content, or lends it to the pending node.
  const showInline = (inline: boolean): void => {
    if (inline) {
      content.setAttribute("aria-label", "Suggestion, not accepted");
      setPendingContent(editor, content);
      panel.classList.add("kotoba-suggestion-floating");
      return;
    }
    setPendingContent(editor, null);
    content.removeAttribute("aria-label");
    if (content.parentElement !== panel) panel.insertBefore(content, actions);
    panel.classList.remove("kotoba-suggestion-floating");
    panel.style.removeProperty("left");
    panel.style.removeProperty("top");
    pendingKey = null;
    setReplaced(null);
  };

  // Inline, the status and the buttons go under the suggestion, and the
  // replaced text is struck.
  const placeInline = (): void => {
    const current = active;
    if (current === null || current.display !== "inline" || panel.hidden) return;
    const element = pendingKey === null ? null : editor.getElementByKey(pendingKey);
    if (element !== null) placeOver(panel, options.host, element.getBoundingClientRect(), "bottom");
    const target = current.target;
    const range =
      current.at === "selection" && target !== null && !target.isCollapsed()
        ? editor.getEditorState().read(() => ($isValid(target) ? domRange(editor, target) : null))
        : null;
    setReplaced(range);
  };

  const render = (): void => {
    if (active === null) {
      panel.hidden = true;
      return;
    }
    panel.hidden = false;
    const streaming = active.state === "streaming";
    content.setAttribute("aria-busy", String(streaming));
    status.textContent = streaming ? "Writing…" : active.state === "done" ? "Done" : "Stopped";
    stop.hidden = !streaming;
    accept.hidden = streaming;
    reject.hidden = streaming;
    placeInline();
  };

  const notify = (ref: string, action: "accept" | "reject" | "stop", detail: Record<string, unknown> = {}): void => {
    options.push?.("kotoba:suggestion", { ...detail, ref, action });
  };

  // The selection at the end of the block that the server names, or `null`.
  const $blockTarget = (block: unknown): RangeSelection | null => {
    let node: LexicalNode | null = null;
    if (typeof block === "number" && Number.isInteger(block) && block >= 1) {
      node = $getRoot().getChildAtIndex(block - 1);
    } else if (typeof block === "string" && block !== "") {
      const key = options.keyOf?.(block) ?? null;
      const found = key === null ? null : $getNodeByKey(key);
      node = found === null || $isRootNode(found) ? null : $findMatchingParent(found, (candidate) => $isRootNode(candidate.getParent()));
    }
    if (!$isElementNode(node)) return null;
    const last = node.getLastDescendant();
    const selection = $createRangeSelection();
    if ($isTextNode(last)) {
      selection.anchor.set(last.getKey(), last.getTextContentSize(), "text");
      selection.focus.set(last.getKey(), last.getTextContentSize(), "text");
    } else {
      const parent = last === null ? node : $isElementNode(last) ? last : last.getParentOrThrow();
      selection.anchor.set(parent.getKey(), parent.getChildrenSize(), "element");
      selection.focus.set(parent.getKey(), parent.getChildrenSize(), "element");
    }
    return selection;
  };

  // The block of a request's selection, for the app to keep: its number, and
  // its id in a shared editor; and there, the selection itself, as a place
  // of the document (`Kotoba.Issho.Place`), for a suggestion that replaces it.
  const $place = (target: RangeSelection | null): Record<string, unknown> | null => {
    if (target === null || !$isValid(target)) return null;
    const focus = target.focus.getNode();
    const block = $isRootNode(focus) ? null : $findMatchingParent(focus, (node) => $isRootNode(node.getParent()));
    if (block === null) return null;
    const id = options.idOf?.(block.getKey()) ?? null;
    if (id === null) return { block: block.getIndexWithinParent() + 1 };
    const selection = target.isCollapsed() ? null : options.sharedOf?.($trimmed(target)) ?? null;
    return { block: block.getIndexWithinParent() + 1, id, ...(selection === null ? {} : { selection }) };
  };

  // The range of a shared selection, when its words are still there.
  const $sharedTarget = (shared: unknown): RangeSelection | null => {
    const points = options.rangeOf?.(shared) ?? null;
    if (points === null) return null;
    const range = $createRangeSelection();
    range.anchor.set(points.anchor.key, points.anchor.offset, points.anchor.type);
    range.focus.set(points.focus.key, points.focus.offset, points.focus.type);
    return $isValid(range) ? range : null;
  };

  // Closes the suggestion. An inline one's pending node goes in an update
  // of its own (not in the history), unless the caller's update takes it
  // away: Lexical joins the updates of a tick, and their tags, so a historic
  // one would keep the caller's change out of the history.
  const close = (removePending = true): void => {
    clearTimeout(idle);
    if (frame !== 0) cancelAnimationFrame(frame);
    frame = 0;
    const inline = active?.display === "inline";
    active = null;
    if (inline) {
      showInline(false);
      if (removePending) editor.update(() => $pendingNodes().forEach((node) => node.remove()), { tag: PENDING_TAGS });
    }
    render();
  };

  // Puts the pending node of an inline suggestion in place (again), and
  // takes away any other.
  const placePending = (): void => {
    const current = active;
    editor.update(
      () => {
        for (const node of $pendingNodes()) node.remove();
        if (current !== null && current.display === "inline") pendingKey = $placePending(current).getKey();
      },
      { tag: PENDING_TAGS, onUpdate: placeInline },
    );
  };

  const armIdle = (): void => {
    clearTimeout(idle);
    idle = setTimeout(() => {
      if (active === null || active.state !== "streaming") return;
      active.state = "stopped";
      notify(active.ref, "stop");
      render();
      options.announce("The suggestion stopped");
    }, STREAM_IDLE_TIMEOUT);
  };

  const doAccept = (): void => {
    const current = active;
    if (current === null || current.state === "streaming") return;
    editor.update(
      () => {
        const nodes = $nodes(current.text, current.format);
        // Inline, the text goes where it was shown; at the caret or over the
        // selection when it was shown below (a word is not split).
        const found = $pendingNodes().find((node) => node.getRef() === current.ref);
        const below = found !== undefined && !found.isInline() && (current.at === "caret" || current.at === "selection");
        const shown = below ? undefined : found;
        for (const node of $pendingNodes()) if (node !== shown) node.remove();
        if (shown !== undefined) {
          $insertAtPending(current, shown, nodes);
          return;
        }
        if (nodes.length === 0) return;
        const { selection, paragraph } = $placeSelection(current);
        selection.insertNodes(nodes);
        if (paragraph !== null && paragraph.isAttached() && paragraph.getTextContent() === "" && $isElementNode(paragraph) && paragraph.isEmpty()) {
          paragraph.remove();
        }
      },
      { tag: HISTORY_PUSH_TAG },
    );
    notify(current.ref, "accept");
    close(false);
    editor.focus();
    options.announce("Suggestion inserted");
  };

  // `restore`: the caret goes back to where the suggestion was asked for;
  // not when the person deleted an inline suggestion, typing over it.
  const doReject = (restore = true): void => {
    const current = active;
    if (current === null) return;
    const streaming = current.state === "streaming";
    notify(current.ref, streaming ? "stop" : "reject");
    close();
    if (!restore) {
      options.announce("Suggestion discarded");
      return;
    }
    editor.update(() => {
      if (current.target !== null && $isValid(current.target)) $setSelection(current.target.clone());
    });
    editor.focus();
    options.announce("Suggestion discarded");
  };

  const doStop = (): void => {
    const current = active;
    if (current === null || current.state !== "streaming") return;
    current.state = "stopped";
    clearTimeout(idle);
    notify(current.ref, "stop");
    render();
    options.announce("Suggestion stopped");
  };

  const onPanelClick = (event: MouseEvent): void => {
    const target = (event.target as Element | null)?.closest("button");
    if (target === accept) doAccept();
    else if (target === reject) doReject();
    else if (target === stop) doStop();
  };

  const onPanelKeyDown = (event: KeyboardEvent): void => {
    if (event.key !== "Escape" || active === null) return;
    event.preventDefault();
    event.stopPropagation();
    if (active.state === "streaming") doStop();
    else doReject();
  };

  panel.addEventListener("click", onPanelClick);
  panel.addEventListener("keydown", onPanelKeyDown);

  // The Assist menu.
  const menu = document.createElement("div");
  menu.className = "kotoba-assist-menu";
  menu.hidden = true;
  menu.setAttribute("role", "menu");
  menu.setAttribute("aria-label", "Assist");
  for (const action of options.actions) {
    const item = document.createElement("button");
    item.type = "button";
    item.className = "kotoba-assist-item";
    item.setAttribute("role", "menuitem");
    item.dataset.kotobaAssist = action.id;
    item.textContent = action.label;
    item.tabIndex = -1;
    menu.append(item);
  }
  options.host.append(menu);

  let opener: HTMLElement | null = null;
  // The selection when the menu opened: the menu takes the focus.
  let menuTarget: { target: RangeSelection | null; text: string } | null = null;
  const items = (): HTMLButtonElement[] => Array.from(menu.querySelectorAll("button"));

  const closeMenu = (focusOpener: boolean): void => {
    menu.hidden = true;
    opener?.setAttribute("aria-expanded", "false");
    if (focusOpener && opener?.isConnected) opener.focus();
  };

  const request = (action: string, detail: Record<string, unknown> = {}, kept = readSelection()): string | null => {
    if (options.push === null) return null;
    const ref = newRef();
    requested.set(ref, { target: kept.target });
    const place = editor.getEditorState().read(() => $place(kept.target));
    options.push("kotoba:assist", { ...detail, ref, action, text: kept.text, ...(place === null ? {} : { place }) });
    options.announce("Asked for a suggestion");
    return ref;
  };

  const onMenuClick = (event: MouseEvent): void => {
    const item = (event.target as Element | null)?.closest<HTMLButtonElement>("[data-kotoba-assist]");
    if (item === null || item === undefined) return;
    const kept = menuTarget ?? readSelection();
    closeMenu(false);
    editor.focus();
    request(item.dataset.kotobaAssist ?? "", {}, kept);
  };

  const onMenuKeyDown = (event: KeyboardEvent): void => {
    const all = items();
    const index = all.indexOf(document.activeElement as HTMLButtonElement);
    let next: number | null = null;
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      closeMenu(true);
      return;
    }
    if (event.key === "ArrowDown" || event.key === "ArrowRight") next = index + 1;
    else if (event.key === "ArrowUp" || event.key === "ArrowLeft") next = index - 1;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = all.length - 1;
    else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      event.stopPropagation();
      if (index !== -1) all[index].click();
      return;
    }
    if (next === null) return;
    event.preventDefault();
    all[(next + all.length) % all.length]?.focus();
  };

  const onMenuFocusOut = (event: FocusEvent): void => {
    if (event.relatedTarget instanceof Node && menu.contains(event.relatedTarget)) return;
    closeMenu(false);
  };

  // A press keeps the focus (and the selection) where it is.
  const onMenuMouseDown = (event: MouseEvent): void => event.preventDefault();

  menu.addEventListener("click", onMenuClick);
  menu.addEventListener("keydown", onMenuKeyDown);
  menu.addEventListener("focusout", onMenuFocusOut);
  menu.addEventListener("mousedown", onMenuMouseDown);

  // The pending node follows the suggestion: a stale one (an undo brought it
  // back) goes; an undo, a redo or a remote change that took the live one
  // away puts it back; the person deleting it rejects the suggestion.
  const onUpdate = ({ editorState, tags }: { editorState: EditorState; tags: Set<string> }): void => {
    if (tags.has(PENDING_TAG)) return;
    const current = active;
    const want = current !== null && current.display === "inline" ? current.ref : null;
    const found = editorState.read(() => $pendingNodes().map((node) => ({ key: node.getKey(), ref: node.getRef() })));
    if (found.some((node) => node.ref !== want)) {
      editor.update(
        () => {
          for (const node of $pendingNodes()) if (node.getRef() !== want) node.remove();
        },
        { tag: PENDING_TAGS },
      );
    }
    if (want === null) return;
    const mine = found.find((node) => node.ref === want);
    if (mine !== undefined) {
      pendingKey = mine.key;
      placeInline();
    } else if (tags.has(HISTORIC_TAG) || tags.has("kotoba-collab") || tags.has("kotoba-remote")) {
      placePending();
    } else {
      doReject(false);
    }
  };

  const onResize = (): void => placeInline();
  window.addEventListener("resize", onResize);

  const unregister = mergeRegister(
    editor.registerUpdateListener(onUpdate),
    editor.registerCommand(
      KEY_DOWN_COMMAND,
      (event: KeyboardEvent) => {
        if (active === null || active.state === "streaming") return false;
        if (!isExactShortcutMatch(event, "Enter", CONTROL_OR_META)) return false;
        event.preventDefault();
        doAccept();
        return true;
      },
      COMMAND_PRIORITY_HIGH,
    ),
    editor.registerCommand(
      KEY_ESCAPE_COMMAND,
      (event: KeyboardEvent) => {
        if (active === null) return false;
        event.preventDefault();
        if (active.state === "streaming") doStop();
        else doReject();
        return true;
      },
      COMMAND_PRIORITY_HIGH,
    ),
  );

  return {
    request: (action, detail) => request(action, detail),

    openMenu(button) {
      if (options.actions.length === 0) return;
      opener = button;
      menuTarget = readSelection();
      menu.hidden = false;
      button.setAttribute("aria-expanded", "true");
      items()[0]?.focus();
    },

    start(ref, start) {
      if (active !== null && active.ref !== ref) {
        notify(active.ref, active.state === "streaming" ? "stop" : "reject");
      }
      const asked = requested.get(ref);
      requested.delete(ref);
      // A selection the server names (a shared one), else a block, else the request's or the editor's.
      const shared = start.selection === undefined ? null : editor.getEditorState().read(() => $sharedTarget(start.selection));
      const named = start.block === undefined ? null : editor.getEditorState().read(() => $blockTarget(start.block));
      const told = start.selection !== undefined || start.block !== undefined;
      const target = shared ?? named ?? (told ? null : asked !== undefined ? asked.target : readSelection().target);
      active = {
        ref,
        at: readTarget(start.at),
        format: readFormat(start.format),
        display: readDisplay(start.display),
        target: target === null ? null : editor.getEditorState().read(() => ($isValid(target) ? $trimmed(target) : target)),
        text: typeof start.text === "string" ? start.text : "",
        state: "streaming",
      };
      showInline(active.display === "inline");
      placePending();
      title.textContent = typeof start.label === "string" && start.label.trim() !== "" ? start.label : "Suggestion";
      panel.setAttribute("aria-label", title.textContent);
      render();
      renderPreview();
      armIdle();
      options.announce(`${title.textContent}: writing`);
    },

    chunk(ref, text) {
      if (active === null || active.ref !== ref || active.state !== "streaming") return;
      active.text += text;
      schedulePreview();
      armIdle();
    },

    end(ref) {
      if (active === null || active.ref !== ref || active.state !== "streaming") return;
      active.state = "done";
      clearTimeout(idle);
      renderPreview();
      render();
      options.announce("Suggestion ready: accept it with Ctrl+Enter, or reject it with Escape");
    },

    cancel(ref) {
      requested.delete(ref);
      if (active === null || active.ref !== ref) return;
      close();
      options.announce("The suggestion was cancelled");
    },

    discard() {
      if (active === null) return;
      notify(active.ref, active.state === "streaming" ? "stop" : "reject");
      close();
    },

    dispose() {
      if (active !== null && active.state === "streaming") notify(active.ref, "stop", { gone: true });
      close();
      unregister();
      window.removeEventListener("resize", onResize);
      preview.setRootElement(null);
      panel.removeEventListener("click", onPanelClick);
      panel.removeEventListener("keydown", onPanelKeyDown);
      menu.removeEventListener("click", onMenuClick);
      menu.removeEventListener("keydown", onMenuKeyDown);
      menu.removeEventListener("focusout", onMenuFocusOut);
      menu.removeEventListener("mousedown", onMenuMouseDown);
      panel.remove();
      menu.remove();
    },
  };
}
