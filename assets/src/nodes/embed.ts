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
  $getSelection,
  $isElementNode,
  $isRangeSelection,
  $isTextNode,
  COMMAND_PRIORITY_LOW,
  DecoratorNode,
  KEY_BACKSPACE_COMMAND,
  KEY_DELETE_COMMAND,
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
