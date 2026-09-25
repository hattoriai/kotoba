// The link form: `Cmd/Ctrl+K` or the toolbar's link button opens it for the
// selected text. Enter applies the URL, an empty URL removes the link, and
// Escape closes the form.

import { $isLinkNode, TOGGLE_LINK_COMMAND } from "@lexical/link";
import { $findMatchingParent } from "@lexical/utils";
import {
  $getSelection,
  $isRangeSelection,
  COMMAND_PRIORITY_NORMAL,
  KEY_DOWN_COMMAND,
  mergeRegister,
  type LexicalEditor,
} from "lexical";

import { isLinkUrl } from "./editor";

export interface LinkForm {
  open(): void;
  dispose(): void;
}

interface LinkOptions {
  host: HTMLElement;
  idPrefix: string;
  announce(message: string): void;
}

/** Reads the URL of the link at the selection, or `null`. */
export function $selectedLinkUrl(): string | null {
  const selection = $getSelection();
  if (!$isRangeSelection(selection)) return null;
  const link = $findMatchingParent(selection.anchor.getNode(), $isLinkNode);
  return $isLinkNode(link) ? link.getURL() : null;
}

/** Adds a scheme to a URL typed without one: "example.com" is "https://example.com". */
export function normalizeUrl(input: string): string {
  const url = input.trim();
  if (url === "" || isLinkUrl(url)) return url;
  if (/^[^\s@/]+@[^\s@/]+\.[^\s@/]+$/.test(url)) return `mailto:${url}`;
  return `https://${url.replace(/^\/+/, "")}`;
}

export function createLinkForm(editor: LexicalEditor, options: LinkOptions): LinkForm {
  const form = document.createElement("form");
  form.className = "kotoba-link-form";
  form.hidden = true;
  form.setAttribute("role", "dialog");
  form.setAttribute("aria-label", "Link");
  form.noValidate = true;

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
  apply.type = "submit";
  apply.className = "kotoba-link-apply";
  apply.textContent = "Apply";

  const remove = document.createElement("button");
  remove.type = "button";
  remove.className = "kotoba-link-remove";
  remove.textContent = "Remove";

  form.append(label, input, apply, remove);
  options.host.append(form);

  const close = (): void => {
    form.hidden = true;
    editor.focus();
  };

  const toggle = (url: string | null): void => {
    editor.update(() => {
      editor.dispatchCommand(TOGGLE_LINK_COMMAND, url);
    });
    options.announce(url === null ? "Link removed" : "Link applied");
    close();
  };

  const open = (): void => {
    if (!editor.isEditable()) return;

    const state = editor.getEditorState().read(() => {
      const selection = $getSelection();
      if (!$isRangeSelection(selection)) return null;
      return { collapsed: selection.isCollapsed(), url: $selectedLinkUrl() };
    });

    if (state === null || (state.collapsed && state.url === null)) {
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

  const onSubmit = (event: SubmitEvent): void => {
    event.preventDefault();
    event.stopPropagation();
    const url = normalizeUrl(input.value);
    if (url === "") {
      toggle(null);
    } else if (isLinkUrl(url)) {
      toggle(url);
    } else {
      options.announce("Enter an http, https or mailto URL");
      input.focus();
    }
  };

  const onKeyDown = (event: KeyboardEvent): void => {
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      close();
    }
  };

  const onRemove = (): void => toggle(null);

  const onFocusOut = (event: FocusEvent): void => {
    if (event.relatedTarget instanceof Node && form.contains(event.relatedTarget)) return;
    form.hidden = true;
  };

  form.addEventListener("submit", onSubmit);
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
        open();
        return true;
      },
      COMMAND_PRIORITY_NORMAL,
    ),
  );

  return {
    open,
    dispose() {
      unregister();
      form.removeEventListener("submit", onSubmit);
      form.removeEventListener("keydown", onKeyDown);
      form.removeEventListener("focusout", onFocusOut);
      remove.removeEventListener("click", onRemove);
      form.remove();
    },
  };
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
