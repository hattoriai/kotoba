// The link form: `Cmd/Ctrl+K` or the toolbar's link button opens it for the
// selected text. Enter applies the URL, an empty URL removes the link, and
// Escape closes the form.
//
// Extensions (`link` in extensions.ts) can list suggestions under the input
// for the text typed (not for a URL): the input is then a combobox, the
// arrow keys move in the list, and Enter applies the suggestion. Or an
// extension opens a form of its own in place of this one.

import { $isLinkNode, $toggleLink } from "@lexical/link";
import { $findMatchingParent } from "@lexical/utils";
import {
  $createRangeSelectionFromDom,
  $getNodeByKey,
  $getSelection,
  $isElementNode,
  $isRangeSelection,
  $isTextNode,
  $setSelection,
  COMMAND_PRIORITY_NORMAL,
  KEY_DOWN_COMMAND,
  mergeRegister,
  type LexicalEditor,
  type RangeSelection,
} from "lexical";

import type { LinkRequest, LinkSuggestion } from "./extensions";
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
  /** The `link` of the editor's extensions, in order, with their context. */
  extensions?: readonly LinkHooks[];
}

/** The time between the last key and the request for suggestions, in milliseconds. */
const SUGGEST_DELAY = 150;
/** The most suggestions that the list shows. */
const SUGGEST_LIMIT = 10;

// A URL, not words to search: a scheme, a path, a fragment or a query, or a
// host name (`example.com`, `example.com/docs`).
const URL_LIKE = /^(?:[a-z][a-z0-9+.-]*:|[/#?]|[^\s/]+\.[a-z]{2,}(?:[/?#:]|$))/i;

/** An extension's `link`, bound to its context. */
export interface LinkHooks {
  suggest?(query: string): readonly LinkSuggestion[] | Promise<readonly LinkSuggestion[]>;
  open?(request: LinkRequest): boolean;
}

interface SelectionState {
  collapsed: boolean;
  url: string | null;
  text: string;
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

  const suggesters = (options.extensions ?? []).flatMap((hooks) => (hooks.suggest === undefined ? [] : [hooks.suggest]));
  const openers = (options.extensions ?? []).flatMap((hooks) => (hooks.open === undefined ? [] : [hooks.open]));

  // The suggestions: a listbox under the input, which is its combobox.
  const list = document.createElement("ul");
  list.id = `${options.idPrefix}-link-suggestions`;
  list.className = "kotoba-menu-list kotoba-link-suggestions";
  list.setAttribute("role", "listbox");
  list.setAttribute("aria-label", "Suggestions");
  list.hidden = true;

  if (suggesters.length > 0) {
    label.textContent = "Link";
    input.placeholder = "Paste a link or search";
    input.setAttribute("role", "combobox");
    input.setAttribute("aria-autocomplete", "list");
    input.setAttribute("aria-expanded", "false");
    input.setAttribute("aria-controls", list.id);
  }

  form.append(label, input, apply, remove, list);
  options.host.append(form);

  let suggestions: LinkSuggestion[] = [];
  let active = -1;
  let asked = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;

  const setActive = (index: number): void => {
    active = index;
    list.querySelectorAll<HTMLElement>("[role=option]").forEach((option, i) => {
      option.setAttribute("aria-selected", String(i === index));
      if (i === index) option.scrollIntoView({ block: "nearest" });
    });
    if (index === -1) input.removeAttribute("aria-activedescendant");
    else input.setAttribute("aria-activedescendant", `${list.id}-${index}`);
  };

  const clearSuggestions = (): void => {
    asked += 1;
    clearTimeout(timer);
    suggestions = [];
    list.replaceChildren();
    list.hidden = true;
    input.setAttribute("aria-expanded", "false");
    setActive(-1);
  };

  const showSuggestions = (query: string, found: LinkSuggestion[]): void => {
    suggestions = found.slice(0, SUGGEST_LIMIT);
    list.replaceChildren(
      ...suggestions.map((suggestion, index) => {
        const option = document.createElement("li");
        option.id = `${list.id}-${index}`;
        option.className = "kotoba-menu-option kotoba-link-suggestion";
        option.setAttribute("role", "option");
        option.setAttribute("aria-selected", "false");
        option.dataset.url = suggestion.url;
        if (suggestion.icon !== undefined) {
          const icon = document.createElement("span");
          icon.className = "kotoba-menu-icon";
          icon.setAttribute("aria-hidden", "true");
          try {
            icon.append(suggestion.icon());
            option.append(icon);
          } catch (error) {
            console.error("Kotoba: the icon of a link suggestion failed", error);
          }
        }
        const text = document.createElement("span");
        text.className = "kotoba-link-suggestion-text";
        const name = document.createElement("span");
        name.className = "kotoba-link-suggestion-label";
        name.textContent = suggestion.label;
        text.append(name);
        if (suggestion.detail !== undefined && suggestion.detail !== "") {
          const detail = document.createElement("span");
          detail.className = "kotoba-menu-hint kotoba-link-suggestion-detail";
          detail.textContent = suggestion.detail;
          text.append(detail);
        }
        option.append(text);
        return option;
      }),
    );
    const open = suggestions.length > 0;
    list.hidden = !open;
    input.setAttribute("aria-expanded", String(open));
    // Words select the first suggestion, so Enter takes it; a URL does not.
    setActive(open && !URL_LIKE.test(query) ? 0 : -1);
    options.announce(open ? `${suggestions.length} suggestion${suggestions.length === 1 ? "" : "s"}` : "No suggestions");
  };

  const suggest = (): void => {
    const query = input.value.trim();
    if (suggesters.length === 0) return;
    if (query === "" || /^[a-z][a-z0-9+.-]*:|^[/#?]/i.test(query)) {
      clearSuggestions();
      return;
    }
    asked += 1;
    const ask = asked;
    clearTimeout(timer);
    timer = setTimeout(() => {
      void Promise.all(
        suggesters.map(async (suggester) => {
          try {
            const found = await suggester(query);
            return Array.isArray(found) ? found.filter(isSuggestion) : [];
          } catch (error) {
            console.error("Kotoba: link suggestions failed", error);
            return [];
          }
        }),
      ).then((lists) => {
        if (ask === asked && !form.hidden) showSuggestions(query, lists.flat());
      });
    }, SUGGEST_DELAY);
  };

  // The selection when the form opened. The link goes on it, even when the
  // editor's selection changed while the focus was in the form.
  let kept: RangeSelection | null = null;

  const close = (): void => {
    form.hidden = true;
    clearSuggestions();
    kept = null;
    editor.focus();
  };

  // `$toggleLink` directly: TOGGLE_LINK_COMMAND takes only absolute URLs
  // (its check also guards paste-to-link), and the form takes relative ones.
  const toggle = (url: string | null): void => {
    const selection = kept;
    editor.update(() => {
      // Else the current selection.
      if (selection !== null && $isValid(selection)) $setSelection(selection.clone());
      $toggleLink(url);
    });
    options.announce(url === null ? "Link removed" : "Link applied");
    close();
  };

  // Reads the selection for the form, in an update. The link goes on this
  // selection when the user applies the URL.
  const $readSelection = (): SelectionState | null => {
    const selection = $domSelection(editor) ?? $getSelection();
    if (!$isRangeSelection(selection)) return null;
    kept = selection.clone();
    return { collapsed: selection.isCollapsed(), url: $selectedLinkUrl(selection), text: selection.getTextContent() };
  };

  // An extension's own form: it gets the selection of this request, which
  // its `apply` keeps.
  const openOwn = (state: SelectionState): boolean => {
    if (openers.length === 0) return false;
    const selection = kept;
    let done = false;
    const request: LinkRequest = {
      url: state.url,
      text: state.text,
      apply: (url) => {
        if (done) return false;
        const normal = url === null ? "" : normalizeUrl(url);
        if (normal !== "" && !isAllowedLinkUrl(normal, options.linkSchemes)) return false;
        done = true;
        kept = selection;
        toggle(normal === "" ? null : normal);
        return true;
      },
    };
    for (const opener of openers) {
      try {
        if (opener(request) === true) return true;
      } catch (error) {
        console.error("Kotoba: an extension's link form failed", error);
      }
    }
    return false;
  };

  const show = (state: SelectionState | null): void => {
    if (state === null || (state.collapsed && state.url === null)) {
      kept = null;
      options.announce("Select text to make a link");
      return;
    }
    if (openOwn(state)) return;

    clearSuggestions();
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
    let state = null as SelectionState | null;
    editor.update(
      () => {
        state = $readSelection();
      },
      { discrete: true },
    );
    show(state);
  };

  const submit = (): void => {
    const chosen = active === -1 ? undefined : suggestions[active];
    const url = normalizeUrl(chosen?.url ?? input.value);
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
    if (event.key === "Escape" && !list.hidden) {
      // The first Escape closes the list, the second the form.
      event.preventDefault();
      event.stopPropagation();
      clearSuggestions();
    } else if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      close();
    } else if ((event.key === "ArrowDown" || event.key === "ArrowUp") && event.target === input && suggestions.length > 0) {
      event.preventDefault();
      const step = event.key === "ArrowDown" ? 1 : -1;
      const count = suggestions.length;
      // From none, Down goes to the first and Up to the last.
      setActive(active === -1 ? (step === 1 ? 0 : count - 1) : (active + step + count) % count);
    } else if (event.key === "Enter" && event.target === input) {
      // Enter in the input would otherwise submit the app's form.
      event.preventDefault();
      event.stopPropagation();
      submit();
    }
  };

  // The input has no name, but its events would still reach the app's form
  // (a phx-change with an empty target).
  const onInput = (event: Event): void => {
    event.stopPropagation();
    if (event.type === "input") suggest();
  };

  // A press on a suggestion keeps the focus in the input; the click applies it.
  const onListPointerDown = (event: PointerEvent): void => event.preventDefault();
  const onListClick = (event: MouseEvent): void => {
    const option = (event.target as Element | null)?.closest<HTMLElement>("[role=option]");
    if (option === null || option === undefined) return;
    const index = [...list.children].indexOf(option);
    if (index === -1) return;
    setActive(index);
    submit();
  };

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
  list.addEventListener("pointerdown", onListPointerDown);
  list.addEventListener("click", onListClick);

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
      list.removeEventListener("pointerdown", onListPointerDown);
      list.removeEventListener("click", onListClick);
      clearTimeout(timer);
      form.remove();
    },
  };
}

function isSuggestion(value: unknown): value is LinkSuggestion {
  if (typeof value !== "object" || value === null) return false;
  const suggestion = value as Record<string, unknown>;
  return (
    typeof suggestion.url === "string" &&
    suggestion.url !== "" &&
    typeof suggestion.label === "string" &&
    suggestion.label.trim() !== "" &&
    (suggestion.detail === undefined || typeof suggestion.detail === "string") &&
    (suggestion.icon === undefined || typeof suggestion.icon === "function")
  );
}

// Lexical reads a change of the DOM selection a moment after it happens, so
// a key press that comes at once (Shift+Arrow, then Cmd+K) would see the
// selection before the change. This reads the DOM selection when it is in
// the editor. It does not set the editor's selection: that would move the
// DOM selection, and the focus, back to the editor.
//
// A selection made from the DOM has no format or style, and Lexical toggles
// a text format from the selection's own format: Bold on bold text would
// apply it again. When the editor's selection is at the same points, this
// returns a copy of it, with its format and style (a format the person
// turned on at a caret too); else it reads them from the text, as Lexical
// does when the DOM selection changes.
export function $domSelection(editor: LexicalEditor): RangeSelection | null {
  const dom = window.getSelection();
  const root = editor.getRootElement();
  if (dom === null || root === null || dom.anchorNode === null || !root.contains(dom.anchorNode)) return null;
  const selection = $createRangeSelectionFromDom(dom, editor);
  if (selection === null) return null;

  const current = $getSelection();
  if ($isRangeSelection(current) && current.anchor.is(selection.anchor) && current.focus.is(selection.focus)) {
    return current.clone();
  }
  $readFormatAndStyle(selection);
  return selection;
}

// A caret takes the format and the style of its text; a range takes the
// formats every selected text node has.
function $readFormatAndStyle(selection: RangeSelection): void {
  if (selection.isCollapsed()) {
    const node = selection.anchor.getNode();
    if ($isTextNode(node)) {
      selection.format = node.getFormat();
      selection.style = node.getStyle();
    } else if ($isElementNode(node) && node.isEmpty()) {
      selection.format = node.getTextFormat();
      selection.style = node.getTextStyle();
    }
    return;
  }

  const [start, end] = selection.isBackward() ? [selection.focus, selection.anchor] : [selection.anchor, selection.focus];
  const nodes = selection.getNodes();
  let format: number | null = null;
  nodes.forEach((node, index) => {
    if (!$isTextNode(node)) return;
    const size = node.getTextContentSize();
    // A text node the range only touches at its edge is not selected.
    if (size === 0) return;
    if (index === 0 && node.getKey() === start.key && start.offset === size) return;
    if (index === nodes.length - 1 && node.getKey() === end.key && end.offset === 0) return;
    format = format === null ? node.getFormat() : format & node.getFormat();
  });
  selection.format = format ?? 0;
}

// A kept selection is still valid when both points are in the document and
// in range: a server push while the form is open can remove, split or
// shorten a text node.
function $isValid(selection: RangeSelection): boolean {
  return [selection.anchor, selection.focus].every((point) => {
    const node = $getNodeByKey(point.key);
    if (node === null || !node.isAttached()) return false;
    if (point.type === "text") return $isTextNode(node) && point.offset <= node.getTextContentSize();
    return $isElementNode(node) && point.offset <= node.getChildrenSize();
  });
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
