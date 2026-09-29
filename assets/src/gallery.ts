// Galleries: images shown together (the `gallery` node, nodes/gallery.ts).
//
// * Shape: a gallery is under the root and holds attachments (and upload
//   markers while images upload). Another child goes after it; a gallery
//   with one attachment becomes that attachment, and an empty one goes.
// * Keyboard: the caret never goes in a gallery. Left and Right select the
//   previous or next image, and past the first or the last one, leave the
//   gallery (as Up and Down do). Right or Down at the end of the block before
//   a gallery selects its first image; Left or Up at the start of the block
//   after it, its last image. Alt+Left and Alt+Right move the selected image;
//   Backspace and Delete remove it and select its neighbour.
// * Group and ungroup: `$groupImages` makes a gallery of an image and the
//   images next to it (empty paragraphs between them go); `$ungroupGallery`
//   puts the images of a gallery back as blocks of their own.
//
// The live region says the position of the selected image ("2 of 3:
// cat.png"), where a moved image is, and what was removed.

import { $findMatchingParent } from "@lexical/utils";
import {
  $addUpdateTag,
  $createNodeSelection,
  $createParagraphNode,
  $getSelection,
  $isDecoratorNode,
  $isElementNode,
  $isNodeSelection,
  $isParagraphNode,
  $isRangeSelection,
  $isRootNode,
  $isTextNode,
  $setSelection,
  COMMAND_PRIORITY_HIGH,
  COMMAND_PRIORITY_LOW,
  HISTORY_MERGE_TAG,
  KEY_ARROW_DOWN_COMMAND,
  KEY_ARROW_LEFT_COMMAND,
  KEY_ARROW_RIGHT_COMMAND,
  KEY_ARROW_UP_COMMAND,
  KEY_BACKSPACE_COMMAND,
  KEY_DELETE_COMMAND,
  KEY_DOWN_COMMAND,
  SELECTION_CHANGE_COMMAND,
  mergeRegister,
  type LexicalEditor,
  type LexicalNode,
  type ParagraphNode,
  type RangeSelection,
} from "lexical";

import { $isAttachmentNode, type AttachmentNode } from "./nodes/attachment";
import { $createGalleryNode, $isGalleryNode, GalleryNode } from "./nodes/gallery";
import { $isUploadMarkerNode } from "./nodes/internal";

/** The image (or file) that is selected alone, and its gallery. */
export interface ImageState {
  /** `true` when the attachment is in a gallery. */
  inGallery: boolean;
  /** Its position in the gallery, from 1 (1 out of a gallery). */
  position: number;
  count: number;
  /** `true` when it is an image with images next to it, out of a gallery. */
  canGroup: boolean;
  canMovePrevious: boolean;
  canMoveNext: boolean;
}

export type GalleryCommand = "gallery" | "image-previous" | "image-next";

/** The attachment that is the whole selection. */
export function $selectedAttachment(): AttachmentNode | null {
  const selection = $getSelection();
  if (!$isNodeSelection(selection)) return null;
  const nodes = selection.getNodes();
  return nodes.length === 1 && $isAttachmentNode(nodes[0]) ? nodes[0] : null;
}

function $galleryOf(node: LexicalNode): GalleryNode | null {
  const parent = node.getParent();
  return $isGalleryNode(parent) ? parent : null;
}

function $selectNode(node: LexicalNode): void {
  const selection = $createNodeSelection();
  selection.add(node.getKey());
  $setSelection(selection);
}

const isImage = (node: LexicalNode | null): node is AttachmentNode => $isAttachmentNode(node) && node.isImage();
const isEmptyParagraph = (node: LexicalNode | null): boolean => $isParagraphNode(node) && node.isEmpty();

// The image, and the images and galleries next to it under the root, with
// the empty paragraphs between them.
function $run(node: AttachmentNode): LexicalNode[] {
  if (!isImage(node) || !$isRootNode(node.getParent())) return [node];
  const collect = (forward: boolean): LexicalNode[] => {
    const found: LexicalNode[] = [];
    const skipped: LexicalNode[] = [];
    let sibling = forward ? node.getNextSibling() : node.getPreviousSibling();
    while (sibling !== null) {
      if (isEmptyParagraph(sibling)) {
        skipped.push(sibling);
      } else if (isImage(sibling) || $isGalleryNode(sibling)) {
        found.push(...skipped, sibling);
        skipped.length = 0;
      } else {
        break;
      }
      sibling = forward ? sibling.getNextSibling() : sibling.getPreviousSibling();
    }
    return found;
  };
  return [...collect(false).reverse(), node, ...collect(true)];
}

/** The state of the selected attachment, or `null` when no attachment is selected alone. */
export function $readImageState(): ImageState | null {
  const node = $selectedAttachment();
  if (node === null) return null;
  const gallery = $galleryOf(node);
  if (gallery === null) {
    const canGroup = $run(node).some((other) => other !== node && !isEmptyParagraph(other));
    return { inGallery: false, position: 1, count: 1, canGroup, canMovePrevious: false, canMoveNext: false };
  }
  const children = gallery.getChildren();
  const index = children.findIndex((child) => child.is(node));
  return {
    inGallery: true,
    position: index + 1,
    count: children.length,
    canGroup: false,
    canMovePrevious: index > 0,
    canMoveNext: index < children.length - 1,
  };
}

/**
 * Makes a gallery of an image and the images and galleries next to it.
 * Returns the gallery, or `null` when there is nothing to group.
 */
export function $groupImages(node: AttachmentNode): GalleryNode | null {
  const run = $run(node);
  const members = run.filter((member) => !isEmptyParagraph(member));
  if (members.length < 2) return null;

  const gallery = $createGalleryNode();
  run[0]?.insertBefore(gallery);
  for (const member of members) {
    if ($isGalleryNode(member)) gallery.append(...member.getChildren());
    else gallery.append(member);
  }
  // The galleries it took the images of, and the empty paragraphs.
  for (const member of run) if ($isGalleryNode(member) || isEmptyParagraph(member)) member.remove();
  $selectNode(node);
  return gallery;
}

/** Puts the images of a gallery back as blocks of their own, in its place. */
export function $ungroupGallery(gallery: GalleryNode): void {
  for (const child of gallery.getChildren()) {
    if (child.isInline()) {
      const paragraph = $createParagraphNode();
      gallery.insertBefore(paragraph);
      paragraph.append(child);
    } else {
      gallery.insertBefore(child);
    }
  }
  gallery.remove();
}

/** Moves an attachment of a gallery one place. Returns `false` at the end of the gallery. */
export function $moveAttachment(node: AttachmentNode, forward: boolean): boolean {
  if ($galleryOf(node) === null) return false;
  const sibling = forward ? node.getNextSibling() : node.getPreviousSibling();
  if (sibling === null) return false;
  if (forward) sibling.insertAfter(node, false);
  else sibling.insertBefore(node, false);
  $selectNode(node);
  return true;
}

function positionLabel(node: AttachmentNode): string {
  const gallery = $galleryOf(node);
  const name = node.getAttachment().name;
  if (gallery === null) return name;
  const children = gallery.getChildren();
  return `${children.findIndex((child) => child.is(node)) + 1} of ${children.length}: ${name}`;
}

/** Runs a command of the toolbar's Image group, and says what it did. */
export function $runGalleryCommand(command: GalleryCommand, announce: (message: string) => void): void {
  const node = $selectedAttachment();
  if (node === null) return;
  const gallery = $galleryOf(node);

  if (command === "gallery") {
    if (gallery !== null) {
      $ungroupGallery(gallery);
      $selectNode(node);
      announce("Gallery ungrouped");
    } else {
      const grouped = $groupImages(node);
      if (grouped !== null) announce(`Gallery of ${grouped.getChildrenSize()} images`);
    }
    return;
  }

  if ($moveAttachment(node, command === "image-next")) announce(`Moved to ${positionLabel(node)}`);
}

// The block that holds the caret, when the caret is at its start (or end).
function $blockAtEdge(selection: RangeSelection, forward: boolean): LexicalNode | null {
  if (!selection.isCollapsed()) return null;
  const point = selection.focus;
  const node = point.getNode();
  const block = node.getTopLevelElement();
  if (block === null) return null;

  if (forward) {
    const size = $isTextNode(node) ? node.getTextContentSize() : $isElementNode(node) ? node.getChildrenSize() : 0;
    if (point.offset !== size) return null;
  } else if (point.offset !== 0) {
    return null;
  }

  let current: LexicalNode = node;
  while (!current.is(block)) {
    if ((forward ? current.getNextSibling() : current.getPreviousSibling()) !== null) return null;
    const parent = current.getParent();
    if (parent === null) return null;
    current = parent;
  }
  return block;
}

// Leaves a gallery: the caret goes into the block next to it, or a decorator
// next to it is selected. With no block next to it, a new paragraph.
function $leave(gallery: GalleryNode, forward: boolean, announce: (message: string) => void): void {
  const sibling = forward ? gallery.getNextSibling() : gallery.getPreviousSibling();
  if ($isGalleryNode(sibling)) {
    const image = forward ? sibling.getFirstChild() : sibling.getLastChild();
    if (image !== null) $selectNode(image);
    if ($isAttachmentNode(image)) announce(positionLabel(image));
  } else if ($isElementNode(sibling)) {
    if (forward) sibling.selectStart();
    else sibling.selectEnd();
  } else if ($isDecoratorNode(sibling)) {
    $selectNode(sibling);
    if ($isAttachmentNode(sibling)) announce(sibling.getAttachment().name);
  } else {
    $addUpdateTag(HISTORY_MERGE_TAG);
    const paragraph = $createParagraphNode();
    if (forward) gallery.insertAfter(paragraph);
    else gallery.insertBefore(paragraph);
    paragraph.select();
  }
}

// Keeps the shape of a gallery (see the top of the file).
function $normalize(gallery: GalleryNode): void {
  const parent = gallery.getParent();
  if (parent !== null && !$isRootNode(parent)) {
    gallery.getTopLevelElement()?.insertAfter(gallery);
    return;
  }

  let after: LexicalNode = gallery;
  let paragraph: ParagraphNode | null = null;
  for (const child of gallery.getChildren()) {
    if ($isAttachmentNode(child) || $isUploadMarkerNode(child)) continue;
    if (child.isInline()) {
      if (paragraph === null) {
        paragraph = $createParagraphNode();
        after.insertAfter(paragraph);
        after = paragraph;
      }
      paragraph.append(child);
    } else {
      after.insertAfter(child);
      after = child;
      paragraph = null;
    }
  }

  const children = gallery.getChildren();
  if (children.length === 0) {
    gallery.remove();
  } else if (children.length === 1 && $isAttachmentNode(children[0])) {
    gallery.insertBefore(children[0]);
    gallery.remove();
  }
}

export interface GalleryOptions {
  announce(message: string): void;
}

export function registerGallery(editor: LexicalEditor, options: GalleryOptions): () => void {
  // Left and Right in a gallery, and into one from the block next to it.
  const arrow = (forward: boolean, horizontal: boolean) => (event: KeyboardEvent) => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return false;
    const selection = $getSelection();
    const node = $selectedAttachment();
    const gallery = node === null ? null : $galleryOf(node);

    if (node !== null && gallery !== null) {
      event.preventDefault();
      const sibling = horizontal ? (forward ? node.getNextSibling() : node.getPreviousSibling()) : null;
      if (sibling !== null && $isDecoratorNode(sibling)) {
        $selectNode(sibling);
        if ($isAttachmentNode(sibling)) options.announce(positionLabel(sibling));
      } else {
        $leave(gallery, forward, options.announce);
      }
      return true;
    }

    // Into a gallery: from the edge of the block next to it, or from a
    // selected block decorator next to it.
    let block: LexicalNode | null = null;
    if ($isRangeSelection(selection)) block = $blockAtEdge(selection, forward);
    else if ($isNodeSelection(selection)) {
      const nodes = selection.getNodes();
      if (nodes.length === 1 && $isRootNode(nodes[0]?.getParent())) block = nodes[0] ?? null;
    }
    const next = block === null ? null : forward ? block.getNextSibling() : block.getPreviousSibling();
    if (!$isGalleryNode(next)) return false;
    const image = forward ? next.getFirstChild() : next.getLastChild();
    if (image === null) return false;
    event.preventDefault();
    $selectNode(image);
    if ($isAttachmentNode(image)) options.announce(positionLabel(image));
    return true;
  };

  const remove = (backward: boolean) => (event: KeyboardEvent | null) => {
    const node = $selectedAttachment();
    const gallery = node === null ? null : $galleryOf(node);
    if (node === null || gallery === null) return false;
    event?.preventDefault();
    const neighbour = backward
      ? (node.getPreviousSibling() ?? node.getNextSibling())
      : (node.getNextSibling() ?? node.getPreviousSibling());
    const name = node.getAttachment().name;
    node.remove();
    if (neighbour !== null) $selectNode(neighbour);
    options.announce(`Removed ${name}`);
    return true;
  };

  // Alt+Left and Alt+Right move the selected image (Lexical sends no arrow
  // command with Alt).
  const move = (event: KeyboardEvent): boolean => {
    const forward = event.key === "ArrowRight";
    if (!event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return false;
    if (!forward && event.key !== "ArrowLeft") return false;
    const node = $selectedAttachment();
    if (node === null || $galleryOf(node) === null) return false;
    event.preventDefault();
    if ($moveAttachment(node, forward)) options.announce(`Moved to ${positionLabel(node)}`);
    else options.announce(forward ? "Already the last image" : "Already the first image");
    return true;
  };

  return mergeRegister(
    editor.registerNodeTransform(GalleryNode, $normalize),
    editor.registerCommand(KEY_DOWN_COMMAND, move, COMMAND_PRIORITY_HIGH),
    editor.registerCommand(KEY_ARROW_LEFT_COMMAND, arrow(false, true), COMMAND_PRIORITY_HIGH),
    editor.registerCommand(KEY_ARROW_RIGHT_COMMAND, arrow(true, true), COMMAND_PRIORITY_HIGH),
    editor.registerCommand(KEY_ARROW_UP_COMMAND, arrow(false, false), COMMAND_PRIORITY_HIGH),
    editor.registerCommand(KEY_ARROW_DOWN_COMMAND, arrow(true, false), COMMAND_PRIORITY_HIGH),
    editor.registerCommand(KEY_BACKSPACE_COMMAND, remove(true), COMMAND_PRIORITY_HIGH),
    editor.registerCommand(KEY_DELETE_COMMAND, remove(false), COMMAND_PRIORITY_HIGH),
    // A caret that lands in a gallery (a click between two images) selects
    // the image there.
    editor.registerCommand(
      SELECTION_CHANGE_COMMAND,
      () => {
        const selection = $getSelection();
        if (!$isRangeSelection(selection)) return false;
        const anchor = selection.anchor.getNode();
        const gallery = $isGalleryNode(anchor) ? anchor : $findMatchingParent(anchor, $isGalleryNode);
        if (!$isGalleryNode(gallery)) return false;
        const children = gallery.getChildren();
        const index = $isGalleryNode(anchor) ? Math.min(selection.anchor.offset, children.length - 1) : 0;
        const image = children[Math.max(index, 0)];
        if (image !== undefined) $selectNode(image);
        return false;
      },
      COMMAND_PRIORITY_LOW,
    ),
  );
}
