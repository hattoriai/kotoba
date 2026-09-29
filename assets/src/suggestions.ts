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
  $getNodeByKey,
  $getRoot,
  $getSelection,
  $isElementNode,
  $isRangeSelection,
  $isRootOrShadowRoot,
  $isTextNode,
  $setSelection,
  COMMAND_PRIORITY_HIGH,
  CONTROL_OR_META,
  HISTORY_PUSH_TAG,
  KEY_DOWN_COMMAND,
  KEY_ESCAPE_COMMAND,
  isExactShortcutMatch,
  mergeRegister,
  type Klass,
  type LexicalEditor,
  type LexicalNode,
  type RangeSelection,
} from "lexical";

import { createKotobaEditor } from "./editor";
import { $domSelection } from "./link";

export type SuggestionTarget = "selection" | "caret" | "after" | "end";
export type SuggestionFormat = "markdown" | "text";

/** An action of the Assist menu. */
export interface AssistAction {
  id: string;
  label: string;
}

export interface StreamStart {
  at?: unknown;
  format?: unknown;
  label?: unknown;
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
}

type State = "streaming" | "done" | "stopped";

interface Active {
  ref: string;
  at: SuggestionTarget;
  format: SuggestionFormat;
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
  };

  const notify = (ref: string, action: "accept" | "reject" | "stop"): void => {
    options.push?.("kotoba:suggestion", { ref, action });
  };

  const close = (): void => {
    clearTimeout(idle);
    if (frame !== 0) cancelAnimationFrame(frame);
    frame = 0;
    active = null;
    render();
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
    close();
    editor.focus();
    options.announce("Suggestion inserted");
  };

  const doReject = (): void => {
    const current = active;
    if (current === null) return;
    const streaming = current.state === "streaming";
    notify(current.ref, streaming ? "stop" : "reject");
    close();
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
    options.push("kotoba:assist", { ...detail, ref, action, text: kept.text });
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

  const unregister = mergeRegister(
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
      active = {
        ref,
        at: readTarget(start.at),
        format: readFormat(start.format),
        target: asked !== undefined ? asked.target : readSelection().target,
        text: "",
        state: "streaming",
      };
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
      if (active !== null && active.state === "streaming") notify(active.ref, "stop");
      close();
      unregister();
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
