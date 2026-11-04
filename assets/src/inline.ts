// Inline elements of an extension: a mark of its own over text (a spoiler,
// a citation, a term), as a link is over text. An extension's node class
// extends Lexical's ElementNode with `isInline()` true; these functions put
// the selected text in such a node, or take it out.
//
//     const $toggleSpoiler = () => inline.$toggle(SpoilerNode, () => new SpoilerNode())
//     toolbar: [{ command: "spoiler", label: "Spoiler", run: (editor) => editor.update($toggleSpoiler),
//                 isActive: () => inline.$isActive(SpoilerNode) }]

import { $findMatchingParent } from "@lexical/utils";
import {
  $getSelection,
  $isElementNode,
  $isRangeSelection,
  $isTextNode,
  type ElementNode,
  type Klass,
  type LexicalNode,
} from "lexical";

/** The inline element of `klass` that holds `node` (or is it), or `null`. */
function $holder(node: LexicalNode, klass: Klass<ElementNode>): ElementNode | null {
  return $findMatchingParent(node, (parent) => parent instanceof klass) as ElementNode | null;
}

// The text of a range selection: its text nodes and inline leaves, without
// the empty text at its edges.
function $selectedLeaves(): LexicalNode[] {
  const selection = $getSelection();
  if (!$isRangeSelection(selection)) return [];
  return selection.getNodes().filter((node) => !$isElementNode(node) && (!$isTextNode(node) || node.getTextContentSize() > 0));
}

/**
 * Whether all the selected text is in an inline element of `klass`. A `$`
 * function: call it in a read or an update of the editor (a toolbar
 * control's `isActive`).
 */
export function $isActive(klass: Klass<ElementNode>): boolean {
  const selection = $getSelection();
  if (!$isRangeSelection(selection)) return false;
  if (selection.isCollapsed()) return $holder(selection.anchor.getNode(), klass) !== null;
  const leaves = $selectedLeaves();
  return leaves.length > 0 && leaves.every((node) => $holder(node, klass) !== null);
}

/**
 * Takes the selected text out of its inline elements of `klass` when all of
 * it is in one (see `$isActive`), else puts it in new ones made by
 * `create`: one for each run of text with the same parent. Text that is in
 * one already stays in it. Call it in an update of the editor.
 */
export function $toggle(klass: Klass<ElementNode>, create: () => ElementNode): void {
  const selection = $getSelection();
  if (!$isRangeSelection(selection) || selection.isCollapsed()) return;

  if ($isActive(klass)) {
    const holders = new Map<string, ElementNode>();
    for (const node of $selectedLeaves()) {
      const holder = $holder(node, klass);
      if (holder !== null) holders.set(holder.getKey(), holder);
    }
    for (const holder of holders.values()) {
      for (const child of holder.getChildren()) holder.insertBefore(child);
      holder.remove();
    }
    return;
  }

  // Splits the text at the edges of the selection: what it returns is
  // only the selected text.
  const extracted = selection.extract().filter((node) => !$isElementNode(node) && $holder(node, klass) === null);
  let wrapper: ElementNode | null = null;
  let first: LexicalNode | null = null;
  let last: LexicalNode | null = null;

  for (const node of extracted) {
    if (node.getParent() === null) continue;
    // The run goes on while the element made for it is just before the
    // node (the node before went into it); else a new run starts here.
    if (wrapper === null || !node.getPreviousSibling()?.is(wrapper)) {
      wrapper = create();
      node.insertBefore(wrapper);
    }
    wrapper.append(node);
    first ??= node;
    last = node;
  }

  if ($isTextNode(first) && $isTextNode(last)) selection.setTextNodeRange(first, 0, last, last.getTextContentSize());
}
