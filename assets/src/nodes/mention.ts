// The `mention` node: a reference to a thing in the app, for example a
// person. The JSON keys mirror `Kotoba.Nodes.Mention`: `kind`, `id` and
// `label`.

import {
  $applyNodeReplacement,
  type LexicalNode,
  type NodeKey,
  type SerializedLexicalNode,
  type SerializedPartial,
  type Spread,
} from "lexical";

import { KotobaDecoratorNode, element } from "./decorator";

export interface MentionPayload {
  kind: string;
  id: string;
  label: string;
}

export type SerializedMentionNode = Spread<MentionPayload, SerializedLexicalNode>;

export class MentionNode extends KotobaDecoratorNode {
  __mention: MentionPayload;

  static getType(): string {
    return "mention";
  }

  static clone(node: MentionNode): MentionNode {
    return new MentionNode(node.__mention, node.__key);
  }

  static importJSON(json: SerializedPartial<SerializedMentionNode>): MentionNode {
    return $createMentionNode({
      kind: String(json.kind ?? ""),
      id: String(json.id ?? ""),
      label: String(json.label ?? ""),
    });
  }

  constructor(mention: MentionPayload, key?: NodeKey) {
    super(key);
    this.__mention = { ...mention };
  }

  exportJSON(): SerializedMentionNode {
    const { kind, id, label } = this.getLatest().__mention;
    return { type: "mention", version: 1, kind, id, label };
  }

  getMention(): MentionPayload {
    return { ...this.getLatest().__mention };
  }

  getTextContent(): string {
    return this.getLatest().__mention.label;
  }

  isInline(): boolean {
    return true;
  }

  className(): string {
    return "kotoba-mention";
  }

  createDOM(config: Parameters<KotobaDecoratorNode["createDOM"]>[0]): HTMLElement {
    const dom = super.createDOM(config);
    dom.dataset.kind = this.__mention.kind;
    dom.dataset.id = this.__mention.id;
    return dom;
  }

  render(): HTMLElement {
    return element("span", "kotoba-mention-label", this.__mention.label);
  }
}

export function $createMentionNode(mention: MentionPayload): MentionNode {
  return $applyNodeReplacement(new MentionNode(mention));
}

export function $isMentionNode(node: LexicalNode | null | undefined): node is MentionNode {
  return node instanceof MentionNode;
}
