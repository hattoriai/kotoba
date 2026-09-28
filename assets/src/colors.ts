// Text and highlight colors (the `highlight` feature).
//
// A color is a name of the palette, stored in the `style` of a text node as
// a CSS custom property of the theme:
//
//     color: var(--kotoba-color-red);background-color: var(--kotoba-highlight-green);
//
// The server reads only these two declarations, with a name of the palette
// (`Kotoba.Nodes.Text.colors/1`), and renders them as classes. A background
// goes with the `highlight` format: the default highlight (yellow, the
// highlight of documents from before the palette) has the format and no
// background. A transform keeps every text node in this form, so a pasted
// style or a color that is not in the palette is dropped.
//
// The Highlight button of the toolbar opens the palette: a dialog with the
// text colors, the highlights and "Remove color". The arrow keys, Home and
// End move in it, Enter or Space applies a color to the selection that the
// palette opened on, and Escape closes it.

import { $patchStyleText } from "@lexical/selection";
import {
  $getNodeByKey,
  $getSelection,
  $isElementNode,
  $isRangeSelection,
  $isTextNode,
  $setSelection,
  $setTextFormat,
  type LexicalEditor,
  type RangeSelection,
  type TextNode,
} from "lexical";

import { $domSelection, position } from "./link";

/** The palette, in its order. `Kotoba.Nodes.Text` has the same list (a test compares them). */
export const COLORS = ["red", "orange", "yellow", "green", "blue", "purple", "gray"] as const;

export type ColorName = (typeof COLORS)[number];

/** The highlight of the `highlight` format with no background. */
export const DEFAULT_HIGHLIGHT: ColorName = "yellow";

const LABELS: Record<ColorName, string> = {
  red: "Red",
  orange: "Orange",
  yellow: "Yellow",
  green: "Green",
  blue: "Blue",
  purple: "Purple",
  gray: "Gray",
};

const TEXT_VAR = /^var\(--kotoba-color-([a-z]+)\)$/;
const HIGHLIGHT_VAR = /^var\(--kotoba-highlight-([a-z]+)\)$/;

function isColor(value: string | undefined): value is ColorName {
  return value !== undefined && (COLORS as readonly string[]).includes(value);
}

export const textColorValue = (name: ColorName): string => `var(--kotoba-color-${name})`;
export const highlightValue = (name: ColorName): string => `var(--kotoba-highlight-${name})`;

function colorOf(value: string | undefined, pattern: RegExp): ColorName | null {
  const name = value?.trim().match(pattern)?.[1];
  return isColor(name) ? name : null;
}

/** Reads the declarations of a CSS text: `{property: value}`, the last one of a property winning. */
function declarations(style: string): Map<string, string> {
  const map = new Map<string, string>();
  for (const part of style.split(";")) {
    const colon = part.indexOf(":");
    if (colon === -1) continue;
    map.set(part.slice(0, colon).trim().toLowerCase(), part.slice(colon + 1).trim());
  }
  return map;
}

/** The colors of a `style`: the ones of the palette, and no other. */
export function colorsOfStyle(style: string): { text: ColorName | null; highlight: ColorName | null } {
  const map = declarations(style);
  return { text: colorOf(map.get("color"), TEXT_VAR), highlight: colorOf(map.get("background-color"), HIGHLIGHT_VAR) };
}

/** The `style` of the colors, in the form that Lexical's `$patchStyleText` writes. */
export function colorStyle(text: ColorName | null, highlight: ColorName | null): string {
  let css = "";
  if (text !== null) css += `color: ${textColorValue(text)};`;
  if (highlight !== null && highlight !== DEFAULT_HIGHLIGHT) css += `background-color: ${highlightValue(highlight)};`;
  return css;
}

/**
 * Keeps a text node's style to the colors of the palette: with `enabled`
 * false (the feature is off), no color at all. A background needs the
 * `highlight` format.
 */
export function $normalizeColors(node: TextNode, enabled: boolean): void {
  const style = node.getStyle();
  if (style === "") return;
  let next = "";
  if (enabled) {
    const { text, highlight } = colorsOfStyle(style);
    next = colorStyle(text, node.hasFormat("highlight") ? highlight : null);
  }
  if (next !== style) node.setStyle(next);
}

/** The colors at the selection: a name, `null` for none, or `"mixed"`. */
export interface ColorState {
  text: ColorName | null | "mixed";
  highlight: ColorName | null | "mixed";
}

export function $readColors(selection: RangeSelection): ColorState {
  if (selection.isCollapsed()) {
    const { text, highlight } = colorsOfStyle(selection.style);
    return { text, highlight: selection.hasFormat("highlight") ? (highlight ?? DEFAULT_HIGHLIGHT) : null };
  }
  const runs = selection
    .getNodes()
    .filter($isTextNode)
    .map((node) => {
      const { text, highlight } = colorsOfStyle(node.getStyle());
      return { text, highlight: node.hasFormat("highlight") ? (highlight ?? DEFAULT_HIGHLIGHT) : null };
    });
  const one = <T>(values: T[]): T | null | "mixed" =>
    values.length === 0 ? null : values.every((value) => value === values[0]) ? values[0] : "mixed";
  return { text: one(runs.map((run) => run.text)), highlight: one(runs.map((run) => run.highlight)) };
}

/** Sets the text color (or none) of the selection. */
export function $setTextColor(selection: RangeSelection, name: ColorName | null): void {
  $patchStyleText(selection, { color: name === null ? null : textColorValue(name) });
}

/** Highlights the selection in a color, or takes its highlight off with `null`. */
export function $setHighlight(selection: RangeSelection, name: ColorName | null): void {
  $setTextFormat(selection, { highlight: name !== null });
  const background = name === null || name === DEFAULT_HIGHLIGHT ? null : highlightValue(name);
  $patchStyleText(selection, { "background-color": background });
}

/** Takes the text color and the highlight off the selection. */
export function $removeColors(selection: RangeSelection): void {
  $setTextFormat(selection, { highlight: false });
  $patchStyleText(selection, { color: null, "background-color": null });
}

export interface ColorMenu {
  /** Opens the palette under the selection, for the toolbar button that opened it. */
  open(button: HTMLElement | null): void;
  dispose(): void;
}

interface ColorMenuOptions {
  host: HTMLElement;
  announce(message: string): void;
}

type Choice = { kind: "text" | "highlight"; name: ColorName } | { kind: "remove" };

export function createColorMenu(editor: LexicalEditor, options: ColorMenuOptions): ColorMenu {
  const menu = document.createElement("div");
  menu.className = "kotoba-color-menu";
  menu.hidden = true;
  menu.setAttribute("role", "dialog");
  menu.setAttribute("aria-label", "Color");

  const choices = new Map<HTMLButtonElement, Choice>();

  const group = (kind: "text" | "highlight", label: string): HTMLElement => {
    const element = document.createElement("div");
    element.className = "kotoba-color-group";
    element.setAttribute("role", "group");
    element.setAttribute("aria-label", label);
    for (const name of COLORS) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `kotoba-color-swatch kotoba-color-swatch-${kind}`;
      const accessible = kind === "text" ? `${LABELS[name]} text` : `${LABELS[name]} highlight`;
      button.setAttribute("aria-label", accessible);
      button.title = accessible;
      button.dataset.kotobaColor = name;
      if (kind === "text") {
        button.style.color = textColorValue(name);
        button.textContent = "A";
      } else {
        button.style.backgroundColor = name === DEFAULT_HIGHLIGHT ? "var(--kotoba-highlight)" : highlightValue(name);
      }
      choices.set(button, { kind, name });
      element.append(button);
    }
    return element;
  };

  const remove = document.createElement("button");
  remove.type = "button";
  remove.className = "kotoba-color-remove";
  remove.textContent = "Remove color";
  choices.set(remove, { kind: "remove" });

  menu.append(group("text", "Text color"), group("highlight", "Highlight"), remove);
  options.host.append(menu);

  // In the order of the page: the text colors, the highlights, Remove.
  const buttons = (): HTMLButtonElement[] => Array.from(menu.querySelectorAll("button"));

  // The selection when the palette opened, and the toolbar button.
  let kept: RangeSelection | null = null;
  let opener: HTMLElement | null = null;

  const setExpanded = (expanded: boolean): void => {
    opener?.setAttribute("aria-expanded", String(expanded));
  };

  const hide = (): void => {
    menu.hidden = true;
    setExpanded(false);
  };

  const showState = (state: ColorState): void => {
    for (const [button, choice] of choices) {
      if (choice.kind === "remove") continue;
      button.setAttribute("aria-pressed", String(state[choice.kind] === choice.name));
    }
  };

  const open = (button: HTMLElement | null): void => {
    if (!editor.isEditable()) return;
    let state: ColorState | null = null;
    editor.update(
      () => {
        const selection = $domSelection(editor) ?? $getSelection();
        if (!$isRangeSelection(selection)) return;
        kept = selection.clone();
        state = $readColors(selection);
      },
      { discrete: true },
    );
    if (state === null) return;

    showState(state);
    opener?.removeAttribute("aria-expanded");
    opener = button;
    menu.hidden = false;
    setExpanded(true);
    position(menu, options.host);
    const pressed = buttons().find((element) => element.getAttribute("aria-pressed") === "true");
    (pressed ?? buttons()[0]).focus();
  };

  const apply = (choice: Choice): void => {
    const selection = kept;
    editor.update(() => {
      if (selection !== null && $isValid(selection)) $setSelection(selection.clone());
      const current = $getSelection();
      if (!$isRangeSelection(current)) return;
      if (choice.kind === "remove") $removeColors(current);
      else if (choice.kind === "text") $setTextColor(current, choice.name);
      else $setHighlight(current, choice.name);
    });
    options.announce(
      choice.kind === "remove"
        ? "Color removed"
        : `${LABELS[choice.name]} ${choice.kind === "text" ? "text" : "highlight"}`,
    );
    kept = null;
    hide();
    editor.focus();
  };

  const onClick = (event: MouseEvent): void => {
    const button = (event.target as Element | null)?.closest("button");
    const choice = button instanceof HTMLButtonElement ? choices.get(button) : undefined;
    if (choice !== undefined) apply(choice);
  };

  // A press keeps the focus where it is, as in the toolbar: the selection
  // stays visible in the editor.
  const onMouseDown = (event: MouseEvent): void => event.preventDefault();

  const onKeyDown = (event: KeyboardEvent): void => {
    const all = buttons();
    const index = all.indexOf(document.activeElement as HTMLButtonElement);
    let next: number | null = null;
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      const back = opener;
      kept = null;
      hide();
      if (back !== null && back.isConnected) back.focus();
      else editor.focus();
      return;
    }
    if (event.key === "ArrowRight" || event.key === "ArrowDown") next = index + 1;
    else if (event.key === "ArrowLeft" || event.key === "ArrowUp") next = index - 1;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = all.length - 1;
    else if (event.key === "Enter") {
      // Enter would otherwise submit the app's form.
      event.preventDefault();
      event.stopPropagation();
      if (index !== -1) all[index].click();
      return;
    }
    if (next === null) return;
    event.preventDefault();
    all[(next + all.length) % all.length].focus();
  };

  const onFocusOut = (event: FocusEvent): void => {
    if (event.relatedTarget instanceof Node && menu.contains(event.relatedTarget)) return;
    hide();
  };

  menu.addEventListener("click", onClick);
  menu.addEventListener("mousedown", onMouseDown);
  menu.addEventListener("keydown", onKeyDown);
  menu.addEventListener("focusout", onFocusOut);

  return {
    open,
    dispose() {
      menu.removeEventListener("click", onClick);
      menu.removeEventListener("mousedown", onMouseDown);
      menu.removeEventListener("keydown", onKeyDown);
      menu.removeEventListener("focusout", onFocusOut);
      menu.remove();
    },
  };
}

// A kept selection is still valid when both points are in the document and
// in range (a server push can change the document while the palette is open).
function $isValid(selection: RangeSelection): boolean {
  return [selection.anchor, selection.focus].every((point) => {
    const node = $getNodeByKey(point.key);
    if (node === null || !node.isAttached()) return false;
    if (point.type === "text") return $isTextNode(node) && point.offset <= node.getTextContentSize();
    return $isElementNode(node) && point.offset <= node.getChildrenSize();
  });
}
