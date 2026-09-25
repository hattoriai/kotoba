// Nodes that only the editor uses. The document on the wire never has them:
// `toEnvelope` drops upload markers and writes unknown nodes back as the JSON
// they were read from.

import {
  $applyNodeReplacement,
  type LexicalNode,
  type NodeKey,
  type SerializedLexicalNode,
  type SerializedPartial,
  type Spread,
} from "lexical";

import { UNKNOWN_TYPE, UPLOAD_MARKER_TYPE, type JSONNode } from "../protocol";
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
