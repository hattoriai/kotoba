// Nodes that only the editor uses. The document on the wire never has them:
// `toEnvelope` drops upload markers and pending suggestions, and writes
// unknown nodes back as the JSON they were read from.

import {
  $applyNodeReplacement,
  type LexicalEditor,
  type LexicalNode,
  type NodeKey,
  type SerializedLexicalNode,
  type SerializedPartial,
  type Spread,
} from "lexical";

import { PENDING_TYPE, UNKNOWN_TYPE, UPLOAD_MARKER_TYPE, type JSONNode } from "../protocol";
import { KotobaDecoratorNode, element } from "./decorator";

type SerializedUploadMarkerNode = Spread<{ name: string }, SerializedLexicalNode>;

/** Holds the place of a file that is uploading, until the server inserts it. */
export class UploadMarkerNode extends KotobaDecoratorNode {
  __name: string;

  static getType(): string {
    return UPLOAD_MARKER_TYPE;
  }

  static clone(node: UploadMarkerNode): UploadMarkerNode {
    return new UploadMarkerNode(node.__name, node.__key);
  }

  static importJSON(json: SerializedPartial<SerializedUploadMarkerNode>): UploadMarkerNode {
    return $createUploadMarkerNode(String(json.name ?? ""));
  }

  constructor(name: string, key?: NodeKey) {
    super(key);
    this.__name = name;
  }

  exportJSON(): SerializedUploadMarkerNode {
    return { type: UPLOAD_MARKER_TYPE, version: 1, name: this.getLatest().__name };
  }

  isInline(): boolean {
    return true;
  }

  className(): string {
    return "kotoba-upload-marker";
  }

  render(): HTMLElement {
    const marker = element("span", "kotoba-upload-marker-label", `Uploading ${this.__name}…`);
    marker.setAttribute("role", "status");
    return marker;
  }
}

export function $createUploadMarkerNode(name: string): UploadMarkerNode {
  return $applyNodeReplacement(new UploadMarkerNode(name));
}

export function $isUploadMarkerNode(node: LexicalNode | null | undefined): node is UploadMarkerNode {
  return node instanceof UploadMarkerNode;
}

type SerializedPendingNode = Spread<{ ref: string; inline: boolean }, SerializedLexicalNode>;

/** The element that a pending suggestion shows, for each editor (see suggestions.ts). */
const PENDING_CONTENT = new WeakMap<LexicalEditor, HTMLElement>();

/** Sets the element that the pending suggestion of `editor` shows, or `null` for none. */
export function setPendingContent(editor: LexicalEditor, content: HTMLElement | null): void {
  if (content === null) PENDING_CONTENT.delete(editor);
  else PENDING_CONTENT.set(editor, content);
}

/**
 * The place of a suggestion that streams in the text (`display: "inline"`):
 * it shows the suggestion where it goes, as a part of the text (inline) or
 * a block. It is not saved, not shared and not copied, and not in the undo
 * history (see suggestions.ts).
 */
export class PendingNode extends KotobaDecoratorNode {
  __ref: string;
  __inline: boolean;

  static getType(): string {
    return PENDING_TYPE;
  }

  static clone(node: PendingNode): PendingNode {
    return new PendingNode(node.__ref, node.__inline, node.__key);
  }

  static importJSON(json: SerializedPartial<SerializedPendingNode>): PendingNode {
    return $createPendingNode(String(json.ref ?? ""), json.inline === true);
  }

  constructor(ref: string, inline: boolean, key?: NodeKey) {
    super(key);
    this.__ref = ref;
    this.__inline = inline;
  }

  exportJSON(): SerializedPendingNode {
    const latest = this.getLatest();
    return { type: PENDING_TYPE, version: 1, ref: latest.__ref, inline: latest.__inline };
  }

  getRef(): string {
    return this.getLatest().__ref;
  }

  isInline(): boolean {
    return this.__inline;
  }

  isKeyboardSelectable(): boolean {
    return false;
  }

  excludeFromCopy(): boolean {
    return true;
  }

  className(): string {
    return this.__inline ? "kotoba-pending kotoba-pending-inline" : "kotoba-pending";
  }

  decorate(editor: LexicalEditor): HTMLElement {
    return PENDING_CONTENT.get(editor) ?? this.render();
  }

  render(): HTMLElement {
    return element("span", "kotoba-pending-empty");
  }
}

export function $createPendingNode(ref: string, inline: boolean): PendingNode {
  return $applyNodeReplacement(new PendingNode(ref, inline));
}

export function $isPendingNode(node: LexicalNode | null | undefined): node is PendingNode {
  return node instanceof PendingNode;
}

type SerializedUnknownNode = Spread<{ raw: JSONNode; inline: boolean }, SerializedLexicalNode>;

/**
 * A node of a type that the editor does not know, for example an app node
 * whose module did not load. The editor shows it as an inert chip and keeps
 * its JSON with no change.
 */
export class UnknownNode extends KotobaDecoratorNode {
  __raw: JSONNode;
  __inline: boolean;

  static getType(): string {
    return UNKNOWN_TYPE;
  }

  static clone(node: UnknownNode): UnknownNode {
    return new UnknownNode(node.__raw, node.__inline, node.__key);
  }

  static importJSON(json: SerializedPartial<SerializedUnknownNode>): UnknownNode {
    const raw = json.raw ?? { type: "unknown" };
    return $applyNodeReplacement(new UnknownNode(raw, json.inline === true));
  }

  constructor(raw: JSONNode, inline: boolean, key?: NodeKey) {
    super(key);
    this.__raw = raw;
    this.__inline = inline;
  }

  exportJSON(): SerializedUnknownNode {
    const latest = this.getLatest();
    return { type: UNKNOWN_TYPE, version: 1, raw: latest.__raw, inline: latest.__inline };
  }

  isInline(): boolean {
    return this.__inline;
  }

  className(): string {
    return "kotoba-unknown";
  }

  render(): HTMLElement {
    const chip = element("span", "kotoba-unknown-label", this.__raw.type);
    chip.title = `Content of type “${this.__raw.type}”`;
    return chip;
  }
}
