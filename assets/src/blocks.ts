// Block handles: the `blocks` feature.
//
// Each top-level block of the document (a paragraph, a heading, a list, a
// quote, a code block, a table, a gallery, an embed...) gets a handle in
// the margin when the pointer is over it, as a block editor has:
//
//   * a grip (⋮⋮): dragged, it moves the whole block, and a line shows
//     where it lands; clicked, it opens the block's menu;
//   * a `+`, which adds an empty paragraph below the block.
//
// The menu has Turn into (paragraph, headings, quote, lists, code block and
// the blocks of the app's extensions, as the editor's features allow),
// Duplicate, Delete, and Copy a link to the block. Turn into is there for a
// block of text; a table, a rule or an embed has the other items.
//
// The keyboard: `Alt+Shift+Up` and `Alt+Shift+Down` move the block at the
// caret, and `Cmd/Ctrl+/` opens its menu, whose items the arrow keys move
// between. Escape closes it and gives the caret back. The live region says
// what each command did.
//
// Every change is one update of the editor: one undo step, and, in a shared
// editor, a move of the node in the shared document (another person's caret
// in the block goes with it). A table or a list has one handle, for the
// whole block. An embed or a gallery keeps its own dragging: only the grip
// moves the block.
//
// An extension's node says how it takes part (`blocks` of the extension,
// see extensions.ts): a label and a `create` put it in Turn into, and
// `handle: false` gives its blocks no handle.

import { $createCodeNode, $isCodeNode } from "@lexical/code-core";
import {
  $isListNode,
  INSERT_CHECK_LIST_COMMAND,
  INSERT_ORDERED_LIST_COMMAND,
  INSERT_UNORDERED_LIST_COMMAND,
  REMOVE_LIST_COMMAND,
} from "@lexical/list";
import {
  $createHeadingNode,
  $createQuoteNode,
  $isHeadingNode,
  $isQuoteNode,
  type HeadingTagType,
} from "@lexical/rich-text";
import { $setBlocksType } from "@lexical/selection";
import { $findMatchingParent } from "@lexical/utils";
import {
  $createParagraphNode,
  $createRangeSelection,
  $getNodeByKey,
  $getRoot,
  $getSelection,
  $isDecoratorNode,
  $isElementNode,
  $isNodeSelection,
  $isParagraphNode,
  $isRangeSelection,
  $isRootNode,
  $parseSerializedNode,
  $setSelection,
  COMMAND_PRIORITY_NORMAL,
  CONTROL_OR_META,
  KEY_DOWN_COMMAND,
  isExactShortcutMatch,
  mergeRegister,
  type ElementNode,
  type LexicalEditor,
  type LexicalNode,
  type SerializedLexicalNode,
} from "lexical";

import type { BlockSpec } from "./extensions";
import type { Feature } from "./features";
import { gripVertical, plus, renderIcon } from "./icons";
import { placeOver, type Floating } from "./selection_menu";

/** A block that Turn into makes. */
interface Target {
  /** A toolbar command, "paragraph", or `ext:<type>` for an extension's block. */
  id: string;
  label: string;
  feature?: Feature;
  spec?: BlockSpec;
}

/** The built-in blocks of Turn into, with the feature of each. */
const BUILT_IN_TARGETS: readonly Target[] = [
  { id: "paragraph", label: "Paragraph" },
  { id: "h1", label: "Heading 1", feature: "headings" },
  { id: "h2", label: "Heading 2", feature: "headings" },
  { id: "h3", label: "Heading 3", feature: "headings" },
  { id: "h4", label: "Heading 4", feature: "headings" },
  { id: "quote", label: "Quote", feature: "quotes" },
  { id: "bullet", label: "Bulleted list", feature: "lists" },
  { id: "number", label: "Numbered list", feature: "lists" },
  { id: "check", label: "Check list", feature: "check_lists" },
  { id: "code-block", label: "Code block", feature: "code_blocks" },
];

/** The blocks of Turn into in an editor: the built-in ones of its features, then the extensions' ones. */
export function turnIntoTargets(features: ReadonlySet<Feature>, specs: readonly BlockSpec[]): Target[] {
  return [
    ...BUILT_IN_TARGETS.filter((target) => target.feature === undefined || features.has(target.feature)),
    ...specs.flatMap((spec) =>
      spec.label !== undefined && spec.create !== undefined ? [{ id: `ext:${spec.type}`, label: spec.label, spec }] : [],
    ),
  ];
}

/**
 * What a block is, as a Turn into target (`h5` for a heading that the menu
 * does not offer), or `null` for a block that is not a block of text.
 */
export function $blockKind(node: LexicalNode, specs: readonly BlockSpec[]): string | null {
  if ($isParagraphNode(node)) return "paragraph";
  if ($isHeadingNode(node)) return node.getTag();
  if ($isQuoteNode(node)) return "quote";
  if ($isListNode(node)) return node.getListType();
  if ($isCodeNode(node)) return "code-block";
  const spec = specs.find((entry) => entry.type === node.getType());
  return spec?.create !== undefined && spec.label !== undefined ? `ext:${spec.type}` : null;
}

/** The top-level block of a node. */
function $topBlock(node: LexicalNode | null): LexicalNode | null {
  if (node === null || $isRootNode(node)) return null;
  return $findMatchingParent(node, (candidate) => $isRootNode(candidate.getParent()));
}

/** The top-level block at the caret, or of the selected node. */
export function $caretBlock(): LexicalNode | null {
  const selection = $getSelection();
  if ($isRangeSelection(selection)) {
    const node = selection.anchor.getNode();
    if ($isRootNode(node)) return node.getChildAtIndex(Math.min(selection.anchor.offset, node.getChildrenSize() - 1));
    return $topBlock(node);
  }
  if ($isNodeSelection(selection)) return $topBlock(selection.getNodes()[0] ?? null);
  return null;
}

/** Moves a block one place up (-1) or down (1). Returns `false` at the edge. */
export function $moveBlock(block: LexicalNode, direction: -1 | 1): boolean {
  const sibling = direction < 0 ? block.getPreviousSibling() : block.getNextSibling();
  if (sibling === null) return false;
  if (direction < 0) sibling.insertBefore(block);
  else sibling.insertAfter(block);
  return true;
}

// The JSON of a node with its children, as a document stores it.
function $exportDeep(node: LexicalNode): SerializedLexicalNode {
  const json = node.exportJSON() as SerializedLexicalNode & { children?: SerializedLexicalNode[] };
  if ($isElementNode(node)) json.children = node.getChildren().map($exportDeep);
  return json;
}

/** Puts a copy of a block after it, and the caret at the copy's start. */
export function $duplicateBlock(block: LexicalNode): LexicalNode {
  const copy = $parseSerializedNode($exportDeep(block));
  block.insertAfter(copy);
  if ($isElementNode(copy)) copy.selectStart();
  return copy;
}

/** Deletes a block. The caret goes to the next block (the previous one at the end). */
export function $deleteBlock(block: LexicalNode): void {
  const next = block.getNextSibling();
  const previous = block.getPreviousSibling();
  block.remove();
  if ($getRoot().getChildrenSize() === 0) {
    const paragraph = $createParagraphNode();
    $getRoot().append(paragraph);
    paragraph.select();
  } else if ($isElementNode(next)) {
    next.selectStart();
  } else if ($isElementNode(previous)) {
    previous.selectEnd();
  }
}

// Selects the text from the start of `first` to the end of `last`.
function $selectBlocks(first: LexicalNode, last: LexicalNode): void {
  if (!$isElementNode(first) || !$isElementNode(last)) return;
  const start = first.selectStart();
  const end = last.selectEnd();
  const selection = $createRangeSelection();
  selection.anchor.set(start.anchor.key, start.anchor.offset, start.anchor.type);
  selection.focus.set(end.focus.key, end.focus.offset, end.focus.type);
  $setSelection(selection);
}

// A block that holds blocks (a quote of paragraphs, as Markdown has it)
// gives them up: they take its place. `null` for a block of inline content.
function $unwrapBlocks(block: LexicalNode): LexicalNode[] | null {
  if (!$isElementNode(block) || $isListNode(block)) return null;
  const children = block.getChildren();
  const blocks = children.length > 0 && children.every((child) => ($isElementNode(child) || $isDecoratorNode(child)) && !child.isInline());
  if (!blocks) return null;
  for (const child of children) block.insertBefore(child);
  block.remove();
  return children;
}

const LIST_COMMANDS = {
  bullet: INSERT_UNORDERED_LIST_COMMAND,
  number: INSERT_ORDERED_LIST_COMMAND,
  check: INSERT_CHECK_LIST_COMMAND,
} as const;

/**
 * Turns a block of text into `target`, as the toolbar's commands do (in the
 * update the caller is in). The caret stays where it was, else goes to the
 * end of the block.
 */
export function $turnInto(editor: LexicalEditor, block: LexicalNode, target: Target): void {
  const before = $getSelection()?.clone() ?? null;
  const code = $isCodeNode(block);
  const inner = $unwrapBlocks(block);
  if (inner !== null) $selectBlocks(inner[0], inner[inner.length - 1]);
  else $selectBlocks(block, block);

  if (target.id in LIST_COMMANDS) {
    editor.dispatchCommand(LIST_COMMANDS[target.id as keyof typeof LIST_COMMANDS], undefined);
  } else {
    // A list is paragraphs first: a list item cannot be another block.
    if ($isListNode(block)) editor.dispatchCommand(REMOVE_LIST_COMMAND, undefined);
    const selection = $getSelection();
    const create = target.spec?.create;
    const tag = /^h[1-6]$/.test(target.id) ? (target.id as HeadingTagType) : null;
    if ($isRangeSelection(selection) && (target.id !== "paragraph" || !$isListNode(block))) {
      $setBlocksType(selection, (): ElementNode => {
        if (create !== undefined) return create();
        if (tag !== null) return $createHeadingNode(tag);
        if (target.id === "quote") return $createQuoteNode();
        if (target.id === "code-block") return $createCodeNode();
        return $createParagraphNode();
      });
    }
  }

  // A code block's text is made again as it is highlighted: the caret goes
  // to the end of the block.
  const after = $getSelection();
  const kept =
    $isRangeSelection(before) &&
    !code &&
    target.id !== "code-block" &&
    before.anchor.getNode().isAttached() &&
    before.focus.getNode().isAttached();
  if (kept) $setSelection(before);
  else if ($isRangeSelection(after)) after.anchor.set(after.focus.key, after.focus.offset, after.focus.type);
}

/**
 * A link to the page that scrolls to the block: the page's URL with a text
 * fragment of the block's first words. `null` for a block with no text.
 */
export function blockLink(href: string, text: string): string | null {
  const words = text.trim().split(/\s+/).filter((word) => word !== "");
  if (words.length === 0) return null;
  // A text fragment's words: `-`, `,` and `&` are its syntax.
  const encode = (value: string): string => encodeURIComponent(value).replace(/-/g, "%2D");
  return `${href.split("#")[0]}#:~:text=${encode(words.slice(0, 8).join(" "))}`;
}

export interface BlockHandleOptions {
  /** The positioned element that holds the handle and the menu (the editor's surface). */
  host: HTMLElement;
  /** The hook element: it gets `kotoba-has-blocks`, which makes the margin. */
  root: HTMLElement;
  /** The editable element. */
  editable: HTMLElement;
  idPrefix: string;
  features: ReadonlySet<Feature>;
  /** The blocks of the extensions. */
  blocks: readonly BlockSpec[];
  announce(message: string): void;
}

/** How far the pointer goes on the grip before a press is a drag, in pixels. */
const DRAG_DISTANCE = 4;

interface Drag {
  key: string;
  pointerId: number;
  x: number;
  y: number;
  moved: boolean;
  /** Where the block lands: before or after the block of `key`, or `null` where it is. */
  target: { key: string; before: boolean } | null;
}

/** Gives the top-level blocks of the editor a handle and a menu. */
export function attachBlockHandles(editor: LexicalEditor, options: BlockHandleOptions): Floating {
  const { host, root, editable, announce } = options;
  const specs = options.blocks;
  const targets = turnIntoTargets(options.features, specs);
  const noHandle = new Set(specs.filter((spec) => spec.handle === false).map((spec) => spec.type));

  root.classList.add("kotoba-has-blocks");

  const button = (className: string, label: string, title: string, icon: SVGSVGElement): HTMLButtonElement => {
    const element = document.createElement("button");
    element.type = "button";
    element.className = `kotoba-block-button ${className}`;
    element.setAttribute("aria-label", label);
    element.title = title;
    // The keyboard has the shortcuts: the handles are not tab stops.
    element.tabIndex = -1;
    element.append(icon);
    return element;
  };

  const handle = document.createElement("div");
  handle.className = "kotoba-block-handle";
  handle.hidden = true;
  const add = button("kotoba-block-add", "Add a block below", "Add a block below", renderIcon(plus));
  const grip = button(
    "kotoba-block-grip",
    "Block menu",
    "Drag to move the block, click for its menu",
    renderIcon(gripVertical),
  );
  const menuId = `${options.idPrefix}-block-menu`;
  grip.setAttribute("aria-haspopup", "menu");
  grip.setAttribute("aria-expanded", "false");
  grip.setAttribute("aria-controls", menuId);
  handle.append(add, grip);

  const drop = document.createElement("div");
  drop.className = "kotoba-block-drop";
  drop.hidden = true;
  drop.setAttribute("aria-hidden", "true");

  const menu = document.createElement("div");
  menu.className = "kotoba-block-menu";
  menu.id = menuId;
  menu.hidden = true;
  menu.setAttribute("role", "menu");
  menu.setAttribute("aria-label", "Block");

  host.append(handle, drop, menu);

  // The keys of the top-level blocks that have a handle, in order.
  let keys: string[] = [];
  // The block of the handle.
  let current: string | null = null;
  // The block of the open menu.
  let menuKey: string | null = null;
  let drag: Drag | null = null;
  // A drag ends with a click on the grip: it does not open the menu.
  let dragged = false;
  let frame = 0;

  const $readKeys = (): string[] =>
    $getRoot()
      .getChildren()
      .filter((node) => !noHandle.has(node.getType()))
      .map((node) => node.getKey());

  const rectOf = (key: string): DOMRect | null => editor.getElementByKey(key)?.getBoundingClientRect() ?? null;

  const place = (): void => {
    frame = 0;
    const key = menuKey ?? drag?.key ?? current;
    const rect = key === null ? null : rectOf(key);
    if (key === null || rect === null || !editor.isEditable()) {
      hide();
      return;
    }
    handle.hidden = false;
    const hostRect = host.getBoundingClientRect();
    const element = editor.getElementByKey(key);
    const line = element === null ? Number.NaN : Number.parseFloat(getComputedStyle(element).lineHeight);
    const first = Math.min(rect.height, Number.isFinite(line) ? line : rect.height);
    const top = rect.top - hostRect.top + Math.max(0, (first - handle.offsetHeight) / 2);
    const left = Math.max(
      editable.getBoundingClientRect().left - hostRect.left + 2,
      rect.left - hostRect.left - handle.offsetWidth - 4,
    );
    handle.style.top = `${Math.round(top)}px`;
    handle.style.left = `${Math.round(left)}px`;
    if (!menu.hidden) placeOver(menu, host, grip.getBoundingClientRect(), "bottom");
  };

  const schedule = (): void => {
    if (frame === 0) frame = requestAnimationFrame(place);
  };

  const hide = (): void => {
    if (menuKey !== null || drag !== null) return;
    handle.hidden = true;
    current = null;
  };

  // The block whose lines are at `y`: the nearest one.
  const blockAt = (y: number): string | null => {
    let best: string | null = null;
    let distance = Number.POSITIVE_INFINITY;
    for (const key of keys) {
      const rect = rectOf(key);
      if (rect === null) continue;
      const away = y < rect.top ? rect.top - y : y > rect.bottom ? y - rect.bottom : 0;
      if (away < distance) {
        best = key;
        distance = away;
      }
    }
    return best;
  };

  const onHover = (event: PointerEvent): void => {
    if (drag !== null || menuKey !== null || !editor.isEditable()) return;
    const target = event.target as Node | null;
    if (target === null || !(editable.contains(target) || handle.contains(target))) {
      hide();
      return;
    }
    if (handle.contains(target)) return;
    const key = blockAt(event.clientY);
    if (key !== current) {
      current = key;
      schedule();
    }
  };

  const onLeave = (): void => hide();

  // Dragging the grip.

  // Where the block lands for the pointer at `y`: before the first block
  // whose middle is below it, else after the last block.
  const dropAt = (y: number, moving: string): Drag["target"] => {
    let target: { key: string; before: boolean } | null = null;
    for (const key of keys) {
      const rect = rectOf(key);
      if (rect !== null && y < rect.top + rect.height / 2) {
        target = { key, before: true };
        break;
      }
    }
    if (target === null && keys.length > 0) target = { key: keys[keys.length - 1], before: false };
    if (target === null) return null;
    // Where the block already is.
    const index = keys.indexOf(moving);
    const at = keys.indexOf(target.key);
    if (target.key === moving || (target.before && at === index + 1) || (!target.before && at === index - 1)) return null;
    return target;
  };

  const showDrop = (target: Drag["target"]): void => {
    const rect = target === null ? null : rectOf(target.key);
    if (target === null || rect === null) {
      drop.hidden = true;
      return;
    }
    const hostRect = host.getBoundingClientRect();
    const index = keys.indexOf(target.key);
    const neighbour = keys[target.before ? index - 1 : index + 1];
    const other = neighbour === undefined ? null : rectOf(neighbour);
    // Half way between the two blocks, or just outside the first or last one.
    const y = target.before
      ? other === null ? rect.top - 2 : (other.bottom + rect.top) / 2
      : other === null ? rect.bottom + 2 : (rect.bottom + other.top) / 2;
    const editableRect = editable.getBoundingClientRect();
    const style = getComputedStyle(editable);
    const left = editableRect.left + Number.parseFloat(style.paddingLeft || "0");
    const right = editableRect.right - Number.parseFloat(style.paddingRight || "0");
    drop.hidden = false;
    drop.style.top = `${Math.round(y - hostRect.top - drop.offsetHeight / 2)}px`;
    drop.style.left = `${Math.round(left - hostRect.left)}px`;
    drop.style.width = `${Math.round(right - left)}px`;
  };

  const endDrag = (commit: boolean): void => {
    const ended = drag;
    if (ended === null) return;
    drag = null;
    drop.hidden = true;
    root.classList.remove("kotoba-block-dragging");
    if (grip.hasPointerCapture(ended.pointerId)) grip.releasePointerCapture(ended.pointerId);
    document.removeEventListener("keydown", onDragKeyDown, true);
    if (!ended.moved) return;
    dragged = true;
    const target = ended.target;
    if (!commit || target === null) {
      schedule();
      return;
    }
    editor.update(() => {
      const block = $getNodeByKey(ended.key);
      const other = $getNodeByKey(target.key);
      if (block === null || other === null || !block.isAttached() || !other.isAttached()) return;
      if (target.before) other.insertBefore(block);
      else other.insertAfter(block);
    });
    announce("Block moved");
    current = ended.key;
    schedule();
  };

  const onDragKeyDown = (event: KeyboardEvent): void => {
    if (event.key !== "Escape") return;
    event.preventDefault();
    event.stopPropagation();
    endDrag(false);
  };

  const onGripDown = (event: PointerEvent): void => {
    if (event.button !== 0 || current === null || !editor.isEditable()) return;
    // The focus and the caret stay in the editor, and no text is selected.
    event.preventDefault();
    dragged = false;
    drag = { key: current, pointerId: event.pointerId, x: event.clientX, y: event.clientY, moved: false, target: null };
    grip.setPointerCapture(event.pointerId);
    document.addEventListener("keydown", onDragKeyDown, true);
  };

  const onGripMove = (event: PointerEvent): void => {
    if (drag === null || event.pointerId !== drag.pointerId) return;
    if (!drag.moved && Math.hypot(event.clientX - drag.x, event.clientY - drag.y) < DRAG_DISTANCE) return;
    if (!drag.moved) closeMenu(false);
    drag.moved = true;
    root.classList.add("kotoba-block-dragging");
    drag.target = dropAt(event.clientY, drag.key);
    showDrop(drag.target);
  };

  const onGripUp = (event: PointerEvent): void => {
    if (drag !== null && event.pointerId === drag.pointerId) endDrag(true);
  };

  const onGripCancel = (event: PointerEvent): void => {
    if (drag !== null && event.pointerId === drag.pointerId) endDrag(false);
  };

  const onGripClick = (event: MouseEvent): void => {
    event.preventDefault();
    if (dragged) {
      dragged = false;
      return;
    }
    if (current === null) return;
    if (menuKey !== null) closeMenu(true);
    else openMenu(current);
  };

  const onAddClick = (event: MouseEvent): void => {
    event.preventDefault();
    const key = current;
    if (key === null || !editor.isEditable()) return;
    editor.update(() => {
      const block = $getNodeByKey(key);
      if (block === null) return;
      const paragraph = $createParagraphNode();
      block.insertAfter(paragraph);
      paragraph.select();
    });
    editor.focus();
    announce("Paragraph added");
  };

  // A press on a button keeps the focus (and the caret) in the editor.
  const onHandleMouseDown = (event: MouseEvent): void => event.preventDefault();

  // The menu.

  const items = (): HTMLButtonElement[] => Array.from(menu.querySelectorAll("button"));

  const menuItem = (label: string, action: string, role = "menuitem"): HTMLButtonElement => {
    const item = document.createElement("button");
    item.type = "button";
    item.className = "kotoba-block-menu-item";
    item.setAttribute("role", role);
    item.dataset.kotobaBlockAction = action;
    item.textContent = label;
    item.tabIndex = -1;
    return item;
  };

  const openMenu = (key: string): void => {
    const info = editor.getEditorState().read(() => {
      const node = $getNodeByKey(key);
      return node === null ? null : { kind: $blockKind(node, specs), text: node.getTextContent() };
    });
    if (info === null) return;

    const children: HTMLElement[] = [];
    if (info.kind !== null && targets.length > 0) {
      const label = document.createElement("div");
      label.className = "kotoba-block-menu-label";
      label.id = `${menuId}-turn`;
      label.textContent = "Turn into";
      const group = document.createElement("div");
      group.setAttribute("role", "group");
      group.setAttribute("aria-labelledby", label.id);
      for (const target of targets) {
        const item = menuItem(target.label, "turn", "menuitemradio");
        item.dataset.kotobaTarget = target.id;
        item.setAttribute("aria-checked", String(target.id === info.kind));
        group.append(item);
      }
      const separator = document.createElement("div");
      separator.className = "kotoba-block-menu-separator";
      separator.setAttribute("role", "separator");
      children.push(label, group, separator);
    }
    children.push(menuItem("Duplicate", "duplicate"), menuItem("Delete", "delete"));
    if (blockLink(window.location.href, info.text) !== null) children.push(menuItem("Copy a link to the block", "link"));
    menu.replaceChildren(...children);

    menuKey = key;
    current = key;
    menu.hidden = false;
    grip.setAttribute("aria-expanded", "true");
    place();
    items()[0]?.focus();
  };

  const closeMenu = (focusEditor: boolean): void => {
    if (menuKey === null) return;
    menuKey = null;
    menu.hidden = true;
    grip.setAttribute("aria-expanded", "false");
    if (focusEditor) editor.focus();
    schedule();
  };

  const runAction = (item: HTMLButtonElement): void => {
    const key = menuKey;
    const action = item.dataset.kotobaBlockAction;
    if (key === null || !editor.isEditable()) return;
    closeMenu(false);

    if (action === "link") {
      const text = editor.getEditorState().read(() => $getNodeByKey(key)?.getTextContent() ?? "");
      const link = blockLink(window.location.href, text);
      editor.focus();
      if (link === null) return;
      navigator.clipboard
        .writeText(link)
        .then(() => announce("Link copied"))
        .catch(() => announce("The link could not be copied"));
      return;
    }

    let message = "";
    editor.update(() => {
      const block = $getNodeByKey(key);
      if (block === null) return;
      if (action === "duplicate") {
        $duplicateBlock(block);
        message = "Block duplicated";
      } else if (action === "delete") {
        $deleteBlock(block);
        message = "Block deleted";
      } else if (action === "turn") {
        const target = targets.find((entry) => entry.id === item.dataset.kotobaTarget);
        if (target === undefined || target.id === $blockKind(block, specs)) return;
        $turnInto(editor, block, target);
        message = `Turned into ${target.label}`;
      }
    });
    editor.focus();
    if (message !== "") announce(message);
  };

  const onMenuClick = (event: MouseEvent): void => {
    const item = (event.target as Element | null)?.closest<HTMLButtonElement>("[data-kotoba-block-action]");
    if (item !== null && item !== undefined && menu.contains(item)) runAction(item);
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
    if (event.key === "ArrowDown") next = index + 1;
    else if (event.key === "ArrowUp") next = index - 1;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = all.length - 1;
    else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      event.stopPropagation();
      if (index !== -1) runAction(all[index]);
      return;
    }
    if (next === null) return;
    event.preventDefault();
    all[(next + all.length) % all.length]?.focus();
  };

  // Tab, or a click elsewhere, leaves the menu: it closes.
  const onMenuFocusOut = (event: FocusEvent): void => {
    if (event.relatedTarget instanceof Node && menu.contains(event.relatedTarget)) return;
    closeMenu(false);
  };

  const onViewportChange = (): void => {
    if (!handle.hidden) schedule();
  };

  // The keyboard, at the caret.
  const onKeyDown = (event: KeyboardEvent): boolean => {
    if (!editor.isEditable()) return false;
    const up = isExactShortcutMatch(event, "ArrowUp", { altKey: true, shiftKey: true });
    const down = isExactShortcutMatch(event, "ArrowDown", { altKey: true, shiftKey: true });
    const opens = event.key === "/" && (CONTROL_OR_META.metaKey ? event.metaKey : event.ctrlKey) && !event.altKey;
    if (!up && !down && !opens) return false;

    // A command listener runs in an update of the editor.
    const block = $caretBlock();
    const key = block?.getKey() ?? null;
    if (block === null || key === null || !keys.includes(key)) return false;
    event.preventDefault();

    if (opens) {
      openMenu(key);
      return true;
    }
    const moved = $moveBlock(block, up ? -1 : 1);
    announce(moved ? (up ? "Block moved up" : "Block moved down") : up ? "The block is the first" : "The block is the last");
    return true;
  };

  host.addEventListener("pointermove", onHover);
  host.addEventListener("pointerleave", onLeave);
  handle.addEventListener("mousedown", onHandleMouseDown);
  grip.addEventListener("pointerdown", onGripDown);
  grip.addEventListener("pointermove", onGripMove);
  grip.addEventListener("pointerup", onGripUp);
  grip.addEventListener("pointercancel", onGripCancel);
  grip.addEventListener("click", onGripClick);
  add.addEventListener("click", onAddClick);
  menu.addEventListener("click", onMenuClick);
  menu.addEventListener("keydown", onMenuKeyDown);
  menu.addEventListener("focusout", onMenuFocusOut);
  menu.addEventListener("mousedown", onHandleMouseDown);
  window.addEventListener("scroll", onViewportChange, true);
  window.addEventListener("resize", onViewportChange);

  const unregister = mergeRegister(
    editor.registerUpdateListener(({ editorState }) => {
      keys = editorState.read($readKeys);
      // A block that is gone (deleted here, or by another person) loses its handle and its menu.
      if (menuKey !== null && !keys.includes(menuKey)) closeMenu(false);
      if (drag !== null && !keys.includes(drag.key)) endDrag(false);
      if (current !== null && !keys.includes(current)) current = null;
      if (!handle.hidden || current !== null) schedule();
    }),
    editor.registerEditableListener((isEditable) => {
      if (isEditable) return;
      endDrag(false);
      closeMenu(false);
      hide();
    }),
    editor.registerCommand(KEY_DOWN_COMMAND, onKeyDown, COMMAND_PRIORITY_NORMAL),
  );

  return {
    dispose() {
      unregister();
      endDrag(false);
      if (frame !== 0) cancelAnimationFrame(frame);
      host.removeEventListener("pointermove", onHover);
      host.removeEventListener("pointerleave", onLeave);
      window.removeEventListener("scroll", onViewportChange, true);
      window.removeEventListener("resize", onViewportChange);
      handle.remove();
      drop.remove();
      menu.remove();
      root.classList.remove("kotoba-has-blocks");
    },
  };
}
