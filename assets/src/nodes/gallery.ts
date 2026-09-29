// The `gallery` node: images shown together, in a grid. Its children are
// attachment nodes (and, while images upload, their upload markers). It
// mirrors `Kotoba.Nodes.Gallery`: a gallery is valid only under the root.
//
// Its DOM is not editable: the caret never goes in it. The person selects
// its images (see gallery.ts, which also keeps its shape).

import {
  $applyNodeReplacement,
  ElementNode,
  type EditorConfig,
  type LexicalNode,
  type NodeKey,
  type SerializedElementNode,
} from "lexical";

export type SerializedGalleryNode = SerializedElementNode;

export class GalleryNode extends ElementNode {
  static getType(): string {
    return "gallery";
  }

  static clone(node: GalleryNode): GalleryNode {
    return new GalleryNode(node.__key);
  }

  static importJSON(json: SerializedGalleryNode): GalleryNode {
    return $createGalleryNode().updateFromJSON(json);
  }

  constructor(key?: NodeKey) {
    super(key);
  }

  createDOM(_config: EditorConfig): HTMLElement {
    const element = document.createElement("div");
    element.className = "kotoba-gallery";
    element.contentEditable = "false";
    element.setAttribute("role", "group");
    element.setAttribute("aria-label", "Gallery");
    return element;
  }

  updateDOM(): boolean {
    return false;
  }

  exportJSON(): SerializedGalleryNode {
    return { ...super.exportJSON(), type: "gallery", version: 1 };
  }

  isInline(): boolean {
    return false;
  }

  canBeEmpty(): boolean {
    return false;
  }

  canIndent(): boolean {
    return false;
  }

  canInsertTextBefore(): boolean {
    return false;
  }

  canInsertTextAfter(): boolean {
    return false;
  }

  isShadowRoot(): boolean {
    return false;
  }
}

export function $createGalleryNode(): GalleryNode {
  return $applyNodeReplacement(new GalleryNode());
}

export function $isGalleryNode(node: LexicalNode | null | undefined): node is GalleryNode {
  return node instanceof GalleryNode;
}
