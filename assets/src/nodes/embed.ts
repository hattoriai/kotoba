// The embed node: a block that holds something live of the app's own (a
// canvas, a grid), which the LiveView renders and teleports into the
// node's slot (Kotoba.Embeds). The node keeps what the app needs to find
// it, `kind` and `ref`, and a `title` for the text and Markdown of the
// document.
//
// The slot is the node's decoration. Kotoba says when a slot comes and
// goes, and the server puts the live content in it with a LiveView portal
// (`<.portal>`). The slot is one element for the node's life, so that the
// content stays as the document changes around it. A deleted node's slot
// waits, empty of the editor, in a hidden element of the hook until the
// server takes its content away: a portal's target must not go first.

import {
  $applyNodeReplacement,
  $createParagraphNode,
  $createTextNode,
  $getNearestNodeFromDOMNode,
  $getNodeByKey,
  $getRoot,
  $getSelection,
  $isDecoratorNode,
  $isParagraphNode,
  $isElementNode,
  $isRangeSelection,
  $isTextNode,
  COMMAND_PRIORITY_LOW,
  COMMAND_PRIORITY_NORMAL,
  DROP_COMMAND,
  DecoratorNode,
  KEY_BACKSPACE_COMMAND,
  KEY_DELETE_COMMAND,
  PASTE_COMMAND,
  mergeRegister,
  type EditorConfig,
  type LexicalEditor,
  type LexicalNode,
  type NodeKey,
  type SerializedLexicalNode,
  type SerializedPartial,
  type Spread,
} from "lexical";

export interface EmbedPayload {
  kind: string;
  ref: string;
  title: string;
}

export type SerializedEmbedNode = Spread<EmbedPayload, SerializedLexicalNode>;

/** What the hook gives the embeds of an editor (`registerEmbeds`). */
export interface EmbedHost {
  /** The id of the editor, the prefix of the ids of its slots. */
  id: string;
  /** Where the slots of deleted nodes wait (an element LiveView ignores). */
  limbo: HTMLElement;
  /** A slot came: the server is to put the content in it. */
  mount(slot: string, embed: EmbedPayload): void;
  /** A slot went. */
  unmount(slot: string): void;
}

interface Embeds {
  host: EmbedHost;
  slots: Map<NodeKey, HTMLElement>;
  mounted: Map<NodeKey, EmbedPayload>;
}

const embeds = new WeakMap<LexicalEditor, Embeds>();

// The events that stay in the slot: what a person types, pastes or drops
// in the embed is the embed's, not the document's.
const OWN_EVENTS = [
  "keydown",
  "keyup",
  "keypress",
  "beforeinput",
  "input",
  "compositionstart",
  "compositionupdate",
  "compositionend",
  "paste",
  "copy",
  "cut",
  "dragover",
  "drop",
] as const;

export class EmbedNode extends DecoratorNode<HTMLElement> {
  __kind: string;
  __ref: string;
  __title: string;

  static getType(): string {
    return "embed";
  }

  static clone(node: EmbedNode): EmbedNode {
    return new EmbedNode({ kind: node.__kind, ref: node.__ref, title: node.__title }, node.__key);
  }

  static importJSON(json: SerializedPartial<SerializedEmbedNode>): EmbedNode {
    return $createEmbedNode({ kind: String(json.kind ?? ""), ref: String(json.ref ?? ""), title: String(json.title ?? "") });
  }

  constructor(embed: EmbedPayload, key?: NodeKey) {
    super(key);
    this.__kind = embed.kind;
    this.__ref = embed.ref;
    this.__title = embed.title;
  }

  exportJSON(): SerializedEmbedNode {
    const self = this.getLatest();
    return { type: "embed", version: 1, kind: self.__kind, ref: self.__ref, title: self.__title };
  }

  getTextContent(): string {
    return this.getLatest().__title;
  }

  isInline(): false {
    return false;
  }

  isKeyboardSelectable(): boolean {
    return true;
  }

  createDOM(_config: EditorConfig): HTMLElement {
    const element = document.createElement("div");
    element.className = "kotoba-embed";
    element.contentEditable = "false";
    element.dataset.kind = this.__kind;
    element.dataset.ref = this.__ref;
    return element;
  }

  updateDOM(): boolean {
    return false;
  }

  decorate(editor: LexicalEditor, _config: EditorConfig): HTMLElement {
    const state = embeds.get(editor);
    const key = this.getKey();
    const payload = { kind: this.__kind, ref: this.__ref, title: this.__title };

    // An editor with no embeds component shows the embed's title.
    if (state === undefined) return placeholder(payload);

    let slot = state.slots.get(key);
    if (slot === undefined) {
      slot = document.createElement("div");
      slot.id = `${state.host.id}-embed-${key}`;
      slot.className = "kotoba-embed-slot";
      for (const type of OWN_EVENTS) slot.addEventListener(type, (event) => event.stopPropagation());
      state.slots.set(key, slot);
    }

    if (!state.mounted.has(key)) {
      state.mounted.set(key, payload);
      const id = slot.id;
      // After the editor has put the slot in the page.
      queueMicrotask(() => state.host.mount(id, payload));
    }
    return slot;
  }
}

function placeholder(embed: EmbedPayload): HTMLElement {
  const element = document.createElement("div");
  element.className = "kotoba-embed-placeholder";
  element.textContent = embed.title || embed.kind;
  return element;
}

export function $createEmbedNode(embed: EmbedPayload): EmbedNode {
  return $applyNodeReplacement(new EmbedNode(embed));
}

export function $isEmbedNode(node: LexicalNode | null | undefined): node is EmbedNode {
  return node instanceof EmbedNode;
}

/**
 * Gives the embeds of `editor` their host: their slots, and the server's
 * content in them. Returns the cleanup, and `resend`, which says every
 * slot again (after a reconnection, when the server has forgotten them).
 */
export function registerEmbeds(editor: LexicalEditor, host: EmbedHost): { cleanup: () => void; resend: () => void } {
  const state: Embeds = { host, slots: new Map(), mounted: new Map() };
  embeds.set(editor, state);

  const unregister = editor.registerMutationListener(
    EmbedNode,
    (mutations) => {
      for (const [key, kind] of mutations) {
        if (kind !== "destroyed" || !state.mounted.has(key)) continue;
        state.mounted.delete(key);
        const slot = state.slots.get(key);
        if (slot === undefined) continue;
        host.limbo.append(slot);
        host.unmount(slot.id);
      }
    },
    { skipInitialization: true },
  );

  return {
    cleanup: () => {
      unregister();
      embeds.delete(editor);
    },
    resend: () => {
      for (const [key, embed] of state.mounted) {
        const slot = state.slots.get(key);
        if (slot !== undefined) host.mount(slot.id, embed);
      }
    },
  };
}

/**
 * Backspace at the start of the block after an embed, and Delete at the
 * end of the block before one, delete the embed, as they delete a
 * horizontal rule (undo brings it back). The caret does not go through an
 * embed: its content is the app's, and the browser would move the caret
 * into it rather than past it.
 */
export function registerEmbedKeys(editor: LexicalEditor): () => void {
  const remove = (backward: boolean) => (event: KeyboardEvent | null): boolean => {
    const selection = $getSelection();
    if (!$isRangeSelection(selection) || !selection.isCollapsed()) return false;
    const anchor = selection.anchor.getNode();
    const block = anchor.getTopLevelElement();
    if (block === null) return false;

    const edge = backward ? block.getFirstDescendant() : block.getLastDescendant();
    const onEdge = edge === null || anchor.is(edge) || anchor.is(block);
    const end = $isTextNode(anchor) ? anchor.getTextContentSize() : $isElementNode(anchor) ? anchor.getChildrenSize() : 0;
    if (!onEdge || selection.anchor.offset !== (backward ? 0 : end)) return false;

    const neighbour = backward ? block.getPreviousSibling() : block.getNextSibling();
    if (!$isEmbedNode(neighbour)) return false;

    event?.preventDefault();
    neighbour.remove();
    return true;
  };

  return mergeRegister(
    editor.registerCommand(KEY_BACKSPACE_COMMAND, remove(true), COMMAND_PRIORITY_LOW),
    editor.registerCommand(KEY_DELETE_COMMAND, remove(false), COMMAND_PRIORITY_LOW),
  );
}

/** Asks the server what a URL is: `reply` gets the embed (`kind`, `ref`, `title`), or `null` for a link. */
export type EmbedResolver = (url: string, reply: (embed: unknown) => void) => void;

const URL_ONLY = /^https?:\/\/\S+$/i;

/** The URL of a paste or a drop that is a URL and nothing else, or `null`. */
export function soleUrl(data: DataTransfer | null): string | null {
  if (data === null || data.types.includes("application/x-lexical-editor")) return null;
  const list = data.getData("text/uri-list").split(/\r?\n/).filter((line) => line !== "" && !line.startsWith("#"));
  const text = (list.length === 1 ? list[0] : data.getData("text/plain")).trim();
  return URL_ONLY.test(text) ? text : null;
}

function embedOf(payload: unknown): EmbedPayload | null {
  if (typeof payload !== "object" || payload === null) return null;
  const { kind, ref, title } = payload as Record<string, unknown>;
  if (typeof kind !== "string" || typeof ref !== "string" || kind === "" || ref === "") return null;
  return { kind, ref, title: typeof title === "string" ? title : "" };
}

/**
 * A link to something the app embeds becomes the embed: a URL pasted alone
 * on an empty line goes in as a link, and becomes the embed when the
 * server says what it is; a URL dropped on the editor goes in after the
 * block it is dropped on, as the embed or else as a link.
 */
export function registerEmbedLinks(
  editor: LexicalEditor,
  options: { resolve: EmbedResolver; announce: (message: string) => void; timeout?: number },
): () => void {
  const ask = (url: string, then: (embed: EmbedPayload | null) => void): void => {
    let done = false;
    const fallback = window.setTimeout(() => {
      if (done) return;
      done = true;
      then(null);
    }, options.timeout ?? 5000);
    options.resolve(url, (payload) => {
      if (done) return;
      done = true;
      window.clearTimeout(fallback);
      then(embedOf(payload));
    });
  };

  const announce = (embed: EmbedPayload): void => options.announce(`Embedded ${embed.title || embed.kind}`);

  return mergeRegister(
    editor.registerCommand(
      PASTE_COMMAND,
      (event) => {
        if (!(event instanceof ClipboardEvent)) return false;
        const url = soleUrl(event.clipboardData);
        const selection = $getSelection();
        if (url === null || !$isRangeSelection(selection) || !selection.isCollapsed()) return false;
        const block = selection.anchor.getNode().getTopLevelElement();
        if (!$isParagraphNode(block) || block.getTextContent() !== "") return false;

        event.preventDefault();
        selection.insertRawText(url);
        const key = block.getKey();
        ask(url, (embed) => {
          if (embed === null) return;
          editor.update(() => {
            const paragraph = $getNodeByKey(key);
            // The person went on writing on the line: it stays a link.
            if (!$isParagraphNode(paragraph) || paragraph.getTextContent().trim() !== url) return;
            const node = $createEmbedNode(embed);
            paragraph.replace(node);
            $afterEmbed(node);
          });
          announce(embed);
        });
        return true;
      },
      // Before the Markdown paste.
      COMMAND_PRIORITY_NORMAL,
    ),
    editor.registerCommand(
      DROP_COMMAND,
      (event) => {
        const url = soleUrl(event.dataTransfer);
        if (url === null) return false;
        const target = event.target instanceof Node ? $getNearestNodeFromDOMNode(event.target) : null;
        const block = target?.getTopLevelElement() ?? (target !== null && $isDecoratorNode(target) ? target : null);
        const key = block?.getKey() ?? null;

        event.preventDefault();
        ask(url, (embed) => {
          editor.update(() => {
            const after = key === null ? null : $getNodeByKey(key);
            const node = embed === null ? $linkParagraph(url) : $createEmbedNode(embed);
            if (after !== null && after.isAttached()) after.insertAfter(node);
            else $getRoot().append(node);
            if (embed !== null) $afterEmbed(node);
            else node.selectEnd();
          });
          if (embed !== null) announce(embed);
        });
        return true;
      },
      COMMAND_PRIORITY_NORMAL,
    ),
  );
}

// A paragraph with the URL as a link.
function $linkParagraph(url: string) {
  const paragraph = $createParagraphNode();
  paragraph.append($createTextNode(url));
  return paragraph;
}

// The caret goes after an embed: on the next block, or a new paragraph.
function $afterEmbed(node: LexicalNode): void {
  const next = node.getNextSibling();
  if ($isParagraphNode(next)) next.selectStart();
  else {
    const paragraph = $createParagraphNode();
    node.insertAfter(paragraph);
    paragraph.select();
  }
}
