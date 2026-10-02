// The selection menu and the link card: two small panels that float over
// the text.
//
// The selection menu shows above a selection of text (below it, when there
// is no room above). It is a toolbar (see toolbar.ts) with a few commands:
// the default ones, the ones of `data-selection-menu`, or the buttons of the
// app's own `[data-kotoba-selection-menu]` element. It waits for the mouse
// button to come up, so that it does not follow a drag, and it does not show
// in a code block, in a read-only editor, or while another panel of the
// editor (the link form, the palette, a prompt menu) is open.
//
// The link card shows under a link when the caret is in it: the URL, which
// opens in a new tab, and Edit and Remove buttons. Cmd/Ctrl+click on a link
// in the editor also opens it.
//
// Alt+F10 moves the focus to the panel that shows (else to the toolbar), and
// Escape closes it until the selection changes.

import { $isCodeNode } from "@lexical/code-core";
import { $isAutoLinkNode, $isLinkNode, type LinkNode } from "@lexical/link";
import { $findMatchingParent } from "@lexical/utils";
import {
  $getSelection,
  $isRangeSelection,
  COMMAND_PRIORITY_NORMAL,
  KEY_DOWN_COMMAND,
  mergeRegister,
  type LexicalEditor,
} from "lexical";

import { externalLink, pencil, renderIcon, unlink } from "./icons";
import { isAllowedLinkUrl } from "./links";
import type { Toolbar } from "./toolbar";

/** The commands of the default selection menu. */
export const SELECTION_MENU_COMMANDS: readonly string[] = [
  "bold",
  "italic",
  "underline",
  "strikethrough",
  "code",
  "highlight",
  "link",
];

/** The space between a panel and the text, in pixels. */
const GAP = 8;

/** The panels of the editor that a floating panel gives way to. */
const BUSY = ".kotoba-link-form:not([hidden]), .kotoba-color-menu:not([hidden]), .kotoba-menu:not([hidden]), .kotoba-assist-menu:not([hidden])";

export interface Floating {
  dispose(): void;
}

interface FloatingOptions {
  /** The positioned element that holds the panel (the editor's surface). */
  host: HTMLElement;
  /** The hook element: the focus in it keeps the panel. */
  root: HTMLElement;
}

/**
 * Places `panel` above `rect` (or below it, when there is no room above in
 * the host and the viewport),
 * centred on it and kept inside the host. The panel gets
 * `data-placement="top"` or `"bottom"`.
 */
export function placeOver(panel: HTMLElement, host: HTMLElement, rect: DOMRect, prefer: "top" | "bottom"): void {
  const hostRect = host.getBoundingClientRect();
  const width = panel.offsetWidth;
  const height = panel.offsetHeight;

  // Above the host's top, the panel would cover the editor's toolbar.
  const roomAbove = rect.top - height - GAP >= Math.max(0, hostRect.top);
  const roomBelow = rect.bottom + height + GAP <= window.innerHeight;
  const placement = prefer === "top" ? (roomAbove || !roomBelow ? "top" : "bottom") : roomBelow || !roomAbove ? "bottom" : "top";

  const top = placement === "top" ? rect.top - hostRect.top - height - GAP : rect.bottom - hostRect.top + GAP;
  const centre = rect.left + rect.width / 2 - hostRect.left;
  const maxLeft = Math.max(0, host.clientWidth - width);
  const left = Math.min(Math.max(0, centre - width / 2), maxLeft);

  panel.style.left = `${Math.round(left)}px`;
  panel.style.top = `${Math.round(top)}px`;
  panel.dataset.placement = placement;
}

// The rectangle of the DOM selection, when it is in the editor.
function selectionRect(editor: LexicalEditor): DOMRect | null {
  const selection = window.getSelection();
  const root = editor.getRootElement();
  if (selection === null || selection.rangeCount === 0 || root === null) return null;
  const range = selection.getRangeAt(0);
  if (!root.contains(range.commonAncestorContainer)) return null;
  const rect = range.getBoundingClientRect();
  return rect.width === 0 && rect.height === 0 ? null : rect;
}

/**
 * Shows the menu `element` (a toolbar made by `createToolbar`) over the
 * selected text.
 */
export function attachSelectionMenu(
  editor: LexicalEditor,
  element: HTMLElement,
  toolbar: Toolbar,
  options: FloatingOptions,
): Floating {
  const { host, root } = options;
  element.classList.add("kotoba-selection-menu");
  element.hidden = true;
  if (element.parentElement !== host) host.append(element);

  let wanted = false;
  let pointerDown = false;
  let dismissed: string | null = null;
  let selectionKey = "";
  let frame = 0;

  const $read = (): { show: boolean; key: string } => {
    const selection = $getSelection();
    if (!$isRangeSelection(selection) || selection.isCollapsed()) return { show: false, key: "" };
    const key = `${selection.anchor.key}:${selection.anchor.offset}:${selection.focus.key}:${selection.focus.offset}`;
    if (selection.getTextContent().trim() === "") return { show: false, key };
    const inCode = selection.getNodes().some((node) => $isCodeNode(node) || $findMatchingParent(node, $isCodeNode) !== null);
    return { show: !inCode, key };
  };

  const focusInside = (): boolean => {
    const active = document.activeElement;
    return active !== null && root.contains(active);
  };

  const update = (): void => {
    frame = 0;
    const show =
      wanted &&
      !pointerDown &&
      dismissed !== selectionKey &&
      editor.isEditable() &&
      focusInside() &&
      host.querySelector(BUSY) === null;

    if (!show) {
      element.hidden = true;
      return;
    }
    const rect = selectionRect(editor);
    if (rect === null) {
      // The focus is on the menu: the DOM selection stays where it was.
      if (!element.contains(document.activeElement)) element.hidden = true;
      return;
    }
    element.hidden = false;
    placeOver(element, host, rect, "top");
  };

  const schedule = (): void => {
    if (frame === 0) frame = requestAnimationFrame(update);
  };

  const onPointerDown = (event: PointerEvent): void => {
    if (element.contains(event.target as Node)) return;
    pointerDown = true;
    element.hidden = true;
  };
  const onPointerUp = (): void => {
    if (!pointerDown) return;
    pointerDown = false;
    schedule();
  };
  const onFocusOut = (event: FocusEvent): void => {
    if (event.relatedTarget instanceof Node && root.contains(event.relatedTarget)) return;
    element.hidden = true;
  };
  const onMenuKeyDown = (event: KeyboardEvent): void => {
    if (event.key !== "Escape") return;
    event.preventDefault();
    event.stopPropagation();
    dismissed = selectionKey;
    element.hidden = true;
    editor.focus();
  };
  const onViewportChange = (): void => {
    if (!element.hidden) schedule();
  };

  document.addEventListener("pointerup", onPointerUp);
  root.addEventListener("focusin", schedule);
  root.addEventListener("focusout", onFocusOut);
  element.addEventListener("keydown", onMenuKeyDown);
  window.addEventListener("scroll", onViewportChange, true);
  window.addEventListener("resize", onViewportChange);

  const unregister = mergeRegister(
    // The editable element is set after the menu is made, and can change.
    editor.registerRootListener((root, previous) => {
      previous?.removeEventListener("pointerdown", onPointerDown);
      root?.addEventListener("pointerdown", onPointerDown);
    }),
    editor.registerUpdateListener(({ editorState }) => {
      const state = editorState.read($read);
      wanted = state.show;
      if (state.key !== selectionKey) {
        selectionKey = state.key;
        dismissed = null;
      }
      schedule();
    }),
    editor.registerEditableListener(schedule),
    editor.registerCommand(
      KEY_DOWN_COMMAND,
      (event: KeyboardEvent) => {
        if (element.hidden) return false;
        if (event.key === "Escape") {
          dismissed = selectionKey;
          element.hidden = true;
          return true;
        }
        if (event.altKey && event.key === "F10" && !event.ctrlKey && !event.metaKey && !event.shiftKey) {
          event.preventDefault();
          toolbar.focus();
          return true;
        }
        return false;
      },
      COMMAND_PRIORITY_NORMAL,
    ),
  );

  return {
    dispose() {
      unregister();
      if (frame !== 0) cancelAnimationFrame(frame);
      editor.getRootElement()?.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("pointerup", onPointerUp);
      root.removeEventListener("focusin", schedule);
      root.removeEventListener("focusout", onFocusOut);
      element.removeEventListener("keydown", onMenuKeyDown);
      window.removeEventListener("scroll", onViewportChange, true);
      window.removeEventListener("resize", onViewportChange);
    },
  };
}

interface LinkCardOptions extends FloatingOptions {
  idPrefix: string;
  linkSchemes: readonly string[];
  /** Opens the link form for the link at the selection. */
  onEdit(): void;
  announce(message: string): void;
}

interface LinkState {
  key: string;
  /** The caret: Escape closes the card until it moves. */
  caret: string;
  url: string;
  auto: boolean;
}

/** Shows the URL of the link at the caret, with Edit and Remove buttons. */
export function attachLinkCard(editor: LexicalEditor, options: LinkCardOptions): Floating {
  const { host, root } = options;

  const card = document.createElement("div");
  card.className = "kotoba-link-card";
  card.hidden = true;
  card.setAttribute("role", "toolbar");
  card.setAttribute("aria-label", "Link");

  const anchor = document.createElement("a");
  anchor.className = "kotoba-link-card-url";
  anchor.target = "_blank";
  anchor.rel = "noopener noreferrer";
  anchor.tabIndex = -1;
  const anchorText = document.createElement("span");
  anchorText.className = "kotoba-link-card-text";
  anchor.append(renderIcon(externalLink), anchorText);

  const button = (className: string, label: string, icon: SVGSVGElement): HTMLButtonElement => {
    const element = document.createElement("button");
    element.type = "button";
    element.className = `kotoba-link-card-button ${className}`;
    element.setAttribute("aria-label", label);
    element.title = label;
    element.tabIndex = -1;
    element.append(icon);
    return element;
  };
  const edit = button("kotoba-link-card-edit", "Edit link", renderIcon(pencil));
  const remove = button("kotoba-link-card-remove", "Remove link", renderIcon(unlink));

  for (const element of [edit, remove]) element.setAttribute("aria-disabled", String(!editor.isEditable()));
  card.append(anchor, edit, remove);
  host.append(card);

  let link: LinkState | null = null;
  let dismissed: string | null = null;
  let frame = 0;

  const $read = (): LinkState | null => {
    const selection = $getSelection();
    if (!$isRangeSelection(selection) || !selection.isCollapsed()) return null;
    const node = $findMatchingParent(selection.anchor.getNode(), $isLinkNode) as LinkNode | null;
    if (node === null) return null;
    const caret = `${selection.anchor.key}:${selection.anchor.offset}`;
    return { key: node.getKey(), caret, url: node.getURL(), auto: $isAutoLinkNode(node) };
  };

  const controls = (): HTMLElement[] => [anchor, edit, remove].filter((element) => !element.hidden);

  const update = (): void => {
    frame = 0;
    const active = document.activeElement;
    const show =
      link !== null &&
      dismissed !== link.caret &&
      editor.isEditable() &&
      active !== null &&
      root.contains(active) &&
      host.querySelector(BUSY) === null;
    const element = show && link !== null ? editor.getElementByKey(link.key) : null;
    if (!show || link === null || element === null) {
      card.hidden = true;
      return;
    }

    const allowed = isAllowedLinkUrl(link.url, options.linkSchemes);
    if (allowed) anchor.href = link.url;
    else anchor.removeAttribute("href");
    anchor.setAttribute("aria-label", `Open ${link.url} in a new tab`);
    anchorText.textContent = link.url;
    edit.hidden = link.auto;
    remove.hidden = link.auto;

    card.hidden = false;
    placeOver(card, host, element.getBoundingClientRect(), "bottom");
  };

  const schedule = (): void => {
    if (frame === 0) frame = requestAnimationFrame(update);
  };

  const close = (): void => {
    if (link !== null) dismissed = link.caret;
    card.hidden = true;
  };

  const onEdit = (): void => {
    if (!editor.isEditable()) return;
    card.hidden = true;
    editor.focus();
    options.onEdit();
  };

  const onRemove = (): void => {
    if (!editor.isEditable()) return;
    const key = link?.key;
    if (key === undefined) return;
    editor.update(() => {
      const node = $getSelection();
      if (!$isRangeSelection(node)) return;
      const target = $findMatchingParent(node.anchor.getNode(), $isLinkNode);
      if (target === null || target.getKey() !== key || !$isLinkNode(target)) return;
      for (const child of target.getChildren()) target.insertBefore(child);
      target.remove();
    });
    options.announce("Link removed");
    editor.focus();
  };

  // A mouse press on the card keeps the focus (and the caret) in the editor.
  const onMouseDown = (event: MouseEvent): void => {
    if ((event.target as Element | null)?.closest("button")) event.preventDefault();
  };

  const onKeyDown = (event: KeyboardEvent): void => {
    const all = controls();
    const index = all.indexOf(document.activeElement as HTMLElement);
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      close();
      editor.focus();
    } else if ((event.key === "ArrowRight" || event.key === "ArrowLeft") && index !== -1) {
      event.preventDefault();
      const next = all[(index + (event.key === "ArrowRight" ? 1 : all.length - 1)) % all.length];
      for (const control of all) control.tabIndex = control === next ? 0 : -1;
      next.focus();
    }
  };

  const onAnchorClick = (): void => {
    card.hidden = true;
  };

  // Cmd/Ctrl+click opens a link of the editor in a new tab.
  const onEditableClick = (event: MouseEvent): void => {
    if (!(event.metaKey || event.ctrlKey)) return;
    const target = (event.target as Element | null)?.closest<HTMLAnchorElement>("a[href]");
    if (!target || !isAllowedLinkUrl(target.getAttribute("href") ?? "", options.linkSchemes)) return;
    event.preventDefault();
    window.open(target.href, "_blank", "noopener,noreferrer");
  };

  const onFocusOut = (event: FocusEvent): void => {
    if (event.relatedTarget instanceof Node && root.contains(event.relatedTarget)) return;
    card.hidden = true;
  };

  const onViewportChange = (): void => {
    if (!card.hidden) schedule();
  };

  card.addEventListener("mousedown", onMouseDown);
  card.addEventListener("keydown", onKeyDown);
  anchor.addEventListener("click", onAnchorClick);
  edit.addEventListener("click", onEdit);
  remove.addEventListener("click", onRemove);
  root.addEventListener("focusin", schedule);
  root.addEventListener("focusout", onFocusOut);
  window.addEventListener("scroll", onViewportChange, true);
  window.addEventListener("resize", onViewportChange);

  const unregister = mergeRegister(
    editor.registerRootListener((root, previous) => {
      previous?.removeEventListener("click", onEditableClick);
      root?.addEventListener("click", onEditableClick);
    }),
    editor.registerUpdateListener(({ editorState }) => {
      const next = editorState.read($read);
      if (next?.caret !== link?.caret) dismissed = null;
      link = next;
      schedule();
    }),
    // As the toolbar's buttons, the card's buttons are disabled in a
    // read-only editor.
    editor.registerEditableListener((editable) => {
      for (const element of [edit, remove]) element.setAttribute("aria-disabled", String(!editable));
      schedule();
    }),
    editor.registerCommand(
      KEY_DOWN_COMMAND,
      (event: KeyboardEvent) => {
        if (card.hidden) return false;
        if (event.key === "Escape") {
          close();
          return true;
        }
        if (event.altKey && event.key === "F10" && !event.ctrlKey && !event.metaKey && !event.shiftKey) {
          event.preventDefault();
          const first = controls()[0];
          for (const control of controls()) control.tabIndex = control === first ? 0 : -1;
          first?.focus();
          return true;
        }
        return false;
      },
      COMMAND_PRIORITY_NORMAL,
    ),
  );

  return {
    dispose() {
      unregister();
      if (frame !== 0) cancelAnimationFrame(frame);
      card.removeEventListener("mousedown", onMouseDown);
      card.removeEventListener("keydown", onKeyDown);
      anchor.removeEventListener("click", onAnchorClick);
      edit.removeEventListener("click", onEdit);
      remove.removeEventListener("click", onRemove);
      editor.getRootElement()?.removeEventListener("click", onEditableClick);
      root.removeEventListener("focusin", schedule);
      root.removeEventListener("focusout", onFocusOut);
      window.removeEventListener("scroll", onViewportChange, true);
      window.removeEventListener("resize", onViewportChange);
      card.remove();
    },
  };
}
