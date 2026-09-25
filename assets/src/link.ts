// The link form: `Cmd/Ctrl+K` or the toolbar's link button opens it for the
// selected text. Enter applies the URL, an empty URL removes the link, and
// Escape closes the form.

import { $isLinkNode, $toggleLink } from "@lexical/link";
import { $findMatchingParent } from "@lexical/utils";
import {
  $createRangeSelectionFromDom,
  $getNodeByKey,
  $getSelection,
  $isRangeSelection,
  $setSelection,
  COMMAND_PRIORITY_NORMAL,
  KEY_DOWN_COMMAND,
  mergeRegister,
  type LexicalEditor,
  type RangeSelection,
} from "lexical";

import { isAllowedLinkUrl, normalizeUrl } from "./links";

export interface LinkForm {
  open(): void;
  dispose(): void;
}

interface LinkOptions {
  host: HTMLElement;
  linkSchemes: readonly string[];
  idPrefix: string;
  announce(message: string): void;
}

/** Reads the URL of the link at the selection, or `null`. */
export function $selectedLinkUrl(selection = $getSelection()): string | null {
  if (!$isRangeSelection(selection)) return null;
  const link = $findMatchingParent(selection.anchor.getNode(), $isLinkNode);
  return $isLinkNode(link) ? link.getURL() : null;
}

export function createLinkForm(editor: LexicalEditor, options: LinkOptions): LinkForm {
  // A div, not a form: the editor is usually inside the app's form, and a
  // form may not hold another form.
  const form = document.createElement("div");
  form.className = "kotoba-link-form";
  form.hidden = true;
  form.setAttribute("role", "dialog");
  form.setAttribute("aria-label", "Link");

  const inputId = `${options.idPrefix}-link-url`;
  const label = document.createElement("label");
  label.htmlFor = inputId;
  label.className = "kotoba-link-label";
  label.textContent = "URL";

  const input = document.createElement("input");
  input.id = inputId;
  input.type = "text";
  input.inputMode = "url";
  input.spellcheck = false;
  input.className = "kotoba-link-input";
  input.placeholder = "https://";

  const apply = document.createElement("button");
  apply.type = "button";
  apply.className = "kotoba-link-apply";
  apply.textContent = "Apply";

  const remove = document.createElement("button");
  remove.type = "button";
  remove.className = "kotoba-link-remove";
  remove.textContent = "Remove";

  form.append(label, input, apply, remove);
  options.host.append(form);

  // The selection when the form opened. The link goes on it, even when the
  // editor's selection changed while the focus was in the form.
  let kept: RangeSelection | null = null;

  const close = (): void => {
    form.hidden = true;
    kept = null;
    editor.focus();
  };

  // `$toggleLink` directly: TOGGLE_LINK_COMMAND takes only absolute URLs
  // (its check also guards paste-to-link), and the form takes relative ones.
  const toggle = (url: string | null): void => {
    const selection = kept;
    editor.update(() => {
      if (selection !== null && $isAttached(selection)) $setSelection(selection.clone());
      $toggleLink(url);
    });
    options.announce(url === null ? "Link removed" : "Link applied");
    close();
  };

  // Reads the selection for the form, in an update. The link goes on this
  // selection when the user applies the URL.
  const $readSelection = (): { collapsed: boolean; url: string | null } | null => {
    const selection = $domSelection(editor) ?? $getSelection();
    if (!$isRangeSelection(selection)) return null;
    kept = selection.clone();
    return { collapsed: selection.isCollapsed(), url: $selectedLinkUrl(selection) };
  };

  const show = (state: { collapsed: boolean; url: string | null } | null): void => {
    if (state === null || (state.collapsed && state.url === null)) {
      kept = null;
      options.announce("Select text to make a link");
      return;
    }

    input.value = state.url ?? "";
    remove.hidden = state.url === null;
    form.hidden = false;
    position(form, options.host);
    input.focus();
    input.select();
  };

  // From the toolbar: outside an update.
  const open = (): void => {
    if (!editor.isEditable()) return;
    let state = null as { collapsed: boolean; url: string | null } | null;
    editor.update(
      () => {
        state = $readSelection();
      },
      { discrete: true },
    );
    show(state);
  };

  const submit = (): void => {
    const url = normalizeUrl(input.value);
    if (url === "") {
      toggle(null);
    } else if (isAllowedLinkUrl(url, options.linkSchemes)) {
      toggle(url);
    } else {
      options.announce(`Enter a relative URL or a URL that starts with ${options.linkSchemes.join(", ")}`);
      input.focus();
    }
  };

  const onKeyDown = (event: KeyboardEvent): void => {
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      close();
    } else if (event.key === "Enter" && event.target === input) {
      // Enter in the input would otherwise submit the app's form.
      event.preventDefault();
      event.stopPropagation();
      submit();
    }
  };

  // The input has no name, but its events would still reach the app's form
  // (a phx-change with an empty target).
  const onInput = (event: Event): void => event.stopPropagation();

  const onRemove = (): void => toggle(null);

  const onFocusOut = (event: FocusEvent): void => {
    if (event.relatedTarget instanceof Node && form.contains(event.relatedTarget)) return;
    form.hidden = true;
  };

  apply.addEventListener("click", submit);
  input.addEventListener("input", onInput);
  input.addEventListener("change", onInput);
  form.addEventListener("keydown", onKeyDown);
  form.addEventListener("focusout", onFocusOut);
  remove.addEventListener("click", onRemove);

  const unregister = mergeRegister(
    editor.registerCommand(
      KEY_DOWN_COMMAND,
      (event: KeyboardEvent) => {
        const modifier = event.metaKey || event.ctrlKey;
        if (!modifier || event.altKey || event.shiftKey || event.key.toLowerCase() !== "k") {
          return false;
        }
        event.preventDefault();
        // A command handler runs in an update, so the selection is read here.
        if (editor.isEditable()) show($readSelection());
        return true;
      },
      COMMAND_PRIORITY_NORMAL,
    ),
  );

  return {
    open,
    dispose() {
      unregister();
      apply.removeEventListener("click", submit);
      input.removeEventListener("input", onInput);
      input.removeEventListener("change", onInput);
      form.removeEventListener("keydown", onKeyDown);
      form.removeEventListener("focusout", onFocusOut);
      remove.removeEventListener("click", onRemove);
      form.remove();
    },
  };
}

// Lexical reads a change of the DOM selection a moment after it happens, so
// a key press that comes at once (Shift+Arrow, then Cmd+K) would see the
// selection before the change. This reads the DOM selection when it is in
// the editor. It does not set the editor's selection: that would move the
// DOM selection, and the focus, back to the editor.
export function $domSelection(editor: LexicalEditor): RangeSelection | null {
  const dom = window.getSelection();
  const root = editor.getRootElement();
  if (dom === null || root === null || dom.anchorNode === null || !root.contains(dom.anchorNode)) return null;
  return $createRangeSelectionFromDom(dom, editor);
}

function $isAttached(selection: RangeSelection): boolean {
  return (
    $getNodeByKey(selection.anchor.key)?.isAttached() === true &&
    $getNodeByKey(selection.focus.key)?.isAttached() === true
  );
}

// Places a floating element under the DOM selection, inside the host.
export function position(floating: HTMLElement, host: HTMLElement): void {
  const selection = window.getSelection();
  const hostRect = host.getBoundingClientRect();
  let left = 0;
  let top = 0;

  if (selection !== null && selection.rangeCount > 0) {
    const rect = selection.getRangeAt(0).getBoundingClientRect();
    if (rect.width !== 0 || rect.height !== 0) {
      left = rect.left - hostRect.left;
      top = rect.bottom - hostRect.top + 4;
    }
  }

  const maxLeft = Math.max(0, host.clientWidth - floating.offsetWidth);
  floating.style.left = `${Math.min(Math.max(0, left), maxLeft)}px`;
  floating.style.top = `${Math.max(0, top)}px`;
}
