// The link form: `Cmd/Ctrl+K` or the toolbar's link button opens it for the
// selected text. Enter applies the URL, an empty URL removes the link, and
// Escape closes the form.

import { $isLinkNode, $toggleLink } from "@lexical/link";
import { $findMatchingParent } from "@lexical/utils";
import {
  $getSelection,
  $isRangeSelection,
  COMMAND_PRIORITY_NORMAL,
  KEY_DOWN_COMMAND,
  mergeRegister,
  type LexicalEditor,
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
export function $selectedLinkUrl(): string | null {
  const selection = $getSelection();
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

  const close = (): void => {
    form.hidden = true;
    editor.focus();
  };

  // `$toggleLink` directly: TOGGLE_LINK_COMMAND takes only absolute URLs
  // (its check also guards paste-to-link), and the form takes relative ones.
  const toggle = (url: string | null): void => {
    editor.update(() => {
      $toggleLink(url);
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
