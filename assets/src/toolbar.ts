// The toolbar: a `role="toolbar"` with a roving tabindex (the arrow keys,
// Home and End move between the buttons) and `aria-pressed` on the buttons
// that reflect the selection.
//
// The hook builds the default toolbar. An app can render its own: a
// `[data-kotoba-toolbar]` element inside the hook element (or anywhere, with
// `data-kotoba-toolbar="<hook element id>"`) that holds buttons with a
// `data-kotoba-command` attribute. The commands are the `command` values of
// `TOOLBAR_ITEMS`.

import { $createCodeNode, $isCodeNode } from "@lexical/code-core";
import { INSERT_HORIZONTAL_RULE_COMMAND } from "@lexical/extension";
import {
  $isListNode,
  INSERT_CHECK_LIST_COMMAND,
  INSERT_ORDERED_LIST_COMMAND,
  INSERT_UNORDERED_LIST_COMMAND,
  ListNode,
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
import { $findMatchingParent, $getNearestNodeOfType } from "@lexical/utils";
import {
  $createParagraphNode,
  $getSelection,
  $isRangeSelection,
  $isRootOrShadowRoot,
  CAN_REDO_COMMAND,
  CAN_UNDO_COMMAND,
  COMMAND_PRIORITY_LOW,
  FORMAT_TEXT_COMMAND,
  REDO_COMMAND,
  UNDO_COMMAND,
  mergeRegister,
  type ElementNode,
  type LexicalEditor,
  type TextFormatType,
} from "lexical";

import { $selectedLinkUrl } from "./link";

export type BlockType =
  | "paragraph"
  | "h1"
  | "h2"
  | "h3"
  | "h4"
  | "h5"
  | "h6"
  | "quote"
  | "bullet"
  | "number"
  | "check"
  | "code-block";

export interface SelectionState {
  formats: Set<TextFormatType>;
  block: BlockType;
  link: boolean;
}

export type ToolbarCommand =
  | "bold"
  | "italic"
  | "strikethrough"
  | "code"
  | "link"
  | "h1"
  | "h2"
  | "h3"
  | "h4"
  | "quote"
  | "bullet"
  | "number"
  | "check"
  | "code-block"
  | "rule"
  | "upload"
  | "undo"
  | "redo";

interface ToolbarItem {
  command: ToolbarCommand;
  label: string;
  text: string;
  group: string;
  shortcut?: string;
}

const MOD = typeof navigator !== "undefined" && /Mac|iP(hone|ad)/.test(navigator.platform) ? "⌘" : "Ctrl+";

export const TOOLBAR_ITEMS: readonly ToolbarItem[] = [
  { command: "bold", label: "Bold", text: "B", group: "Text", shortcut: `${MOD}B` },
  { command: "italic", label: "Italic", text: "I", group: "Text", shortcut: `${MOD}I` },
  { command: "strikethrough", label: "Strikethrough", text: "S", group: "Text" },
  { command: "code", label: "Inline code", text: "</>", group: "Text" },
  { command: "link", label: "Link", text: "Link", group: "Text", shortcut: `${MOD}K` },
  { command: "h1", label: "Heading 1", text: "H1", group: "Blocks" },
  { command: "h2", label: "Heading 2", text: "H2", group: "Blocks" },
  { command: "h3", label: "Heading 3", text: "H3", group: "Blocks" },
  { command: "quote", label: "Quote", text: "“ ”", group: "Blocks" },
  { command: "bullet", label: "Bulleted list", text: "•", group: "Lists" },
  { command: "number", label: "Numbered list", text: "1.", group: "Lists" },
  { command: "check", label: "Check list", text: "☐", group: "Lists" },
  { command: "code-block", label: "Code block", text: "{ }", group: "Insert" },
  { command: "rule", label: "Horizontal rule", text: "—", group: "Insert" },
  { command: "upload", label: "Attach a file", text: "Attach", group: "Insert" },
  { command: "undo", label: "Undo", text: "↶", group: "History", shortcut: `${MOD}Z` },
  { command: "redo", label: "Redo", text: "↷", group: "History" },
];

const COMMANDS = new Set<string>(TOOLBAR_ITEMS.map((item) => item.command).concat("h4"));
const TOGGLE_FORMATS = new Set<string>(["bold", "italic", "strikethrough", "code"]);
const BLOCK_COMMANDS = new Set<string>(["h1", "h2", "h3", "h4", "quote", "bullet", "number", "check", "code-block"]);

function isCommand(value: string | undefined): value is ToolbarCommand {
  return value !== undefined && COMMANDS.has(value);
}

/** Reads the formats, the block type and the link at the selection. */
export function $readSelectionState(): SelectionState {
  const state: SelectionState = { formats: new Set(), block: "paragraph", link: false };
  const selection = $getSelection();
  if (!$isRangeSelection(selection)) return state;

  for (const format of ["bold", "italic", "strikethrough", "code"] as const) {
    if (selection.hasFormat(format)) state.formats.add(format);
  }
  state.link = $selectedLinkUrl() !== null;

  const anchor = selection.anchor.getNode();
  const block =
    anchor.getKey() === "root"
      ? null
      : ($findMatchingParent(anchor, (node) => {
          const parent = node.getParent();
          return parent !== null && $isRootOrShadowRoot(parent);
        }) as ElementNode | null);

  if (block === null) return state;

  if ($isListNode(block)) {
    const list = $getNearestNodeOfType(anchor, ListNode) ?? block;
    state.block = list.getListType();
  } else if ($isHeadingNode(block)) {
    state.block = block.getTag();
  } else if ($isQuoteNode(block)) {
    state.block = "quote";
  } else if ($isCodeNode(block)) {
    state.block = "code-block";
  }
  return state;
}

/** Runs a toolbar command on the editor. */
export function runCommand(editor: LexicalEditor, command: ToolbarCommand, state: SelectionState): void {
  switch (command) {
    case "bold":
    case "italic":
    case "strikethrough":
    case "code":
      editor.dispatchCommand(FORMAT_TEXT_COMMAND, command);
      return;
    case "bullet":
    case "number":
    case "check":
      if (state.block === command) {
        editor.dispatchCommand(REMOVE_LIST_COMMAND, undefined);
      } else if (command === "bullet") {
        editor.dispatchCommand(INSERT_UNORDERED_LIST_COMMAND, undefined);
      } else if (command === "number") {
        editor.dispatchCommand(INSERT_ORDERED_LIST_COMMAND, undefined);
      } else {
        editor.dispatchCommand(INSERT_CHECK_LIST_COMMAND, undefined);
      }
      return;
    case "h1":
    case "h2":
    case "h3":
    case "h4":
    case "quote":
    case "code-block":
      editor.update(() => {
        const selection = $getSelection();
        if (!$isRangeSelection(selection)) return;
        if (state.block === command) {
          $setBlocksType(selection, () => $createParagraphNode());
        } else if (command === "quote") {
          $setBlocksType(selection, () => $createQuoteNode());
        } else if (command === "code-block") {
          $setBlocksType(selection, () => $createCodeNode());
        } else {
          const tag: HeadingTagType = command;
          $setBlocksType(selection, () => $createHeadingNode(tag));
        }
      });
      return;
    case "rule":
      editor.dispatchCommand(INSERT_HORIZONTAL_RULE_COMMAND, undefined);
      return;
    case "undo":
      editor.dispatchCommand(UNDO_COMMAND, undefined);
      return;
    case "redo":
      editor.dispatchCommand(REDO_COMMAND, undefined);
      return;
    case "link":
    case "upload":
      return;
  }
}

export interface Toolbar {
  element: HTMLElement;
  setDisabled(disabled: boolean): void;
  dispose(): void;
}

interface ToolbarOptions {
  /** The app's toolbar, or `null` to build the default one. */
  existing: HTMLElement | null;
  /** Where to put the default toolbar. */
  host: HTMLElement;
  label: string;
  uploads: boolean;
  onLink(): void;
  onUpload(): void;
  announce(message: string): void;
}

export function createToolbar(editor: LexicalEditor, options: ToolbarOptions): Toolbar {
  const toolbar = options.existing ?? buildToolbar(options.uploads);
  if (options.existing === null) options.host.prepend(toolbar);

  toolbar.setAttribute("role", "toolbar");
  if (!toolbar.hasAttribute("aria-label")) toolbar.setAttribute("aria-label", options.label);
  toolbar.classList.add("kotoba-toolbar");

  const buttons = (): HTMLButtonElement[] =>
    Array.from(toolbar.querySelectorAll<HTMLButtonElement>("button[data-kotoba-command]")).filter(
      (button) => !button.hidden && isCommand(button.dataset.kotobaCommand),
    );

  let state: SelectionState = { formats: new Set(), block: "paragraph", link: false };
  let disabled = false;
  const history = { undo: false, redo: false };

  const refresh = (): void => {
    for (const button of buttons()) {
      const command = button.dataset.kotobaCommand as ToolbarCommand;

      if (TOGGLE_FORMATS.has(command)) {
        button.setAttribute("aria-pressed", String(state.formats.has(command as TextFormatType)));
      } else if (BLOCK_COMMANDS.has(command)) {
        button.setAttribute("aria-pressed", String(state.block === command));
      } else if (command === "link") {
        button.setAttribute("aria-pressed", String(state.link));
      }

      const unavailable =
        disabled ||
        (command === "undo" && !history.undo) ||
        (command === "redo" && !history.redo) ||
        (command === "upload" && !options.uploads);
      button.setAttribute("aria-disabled", String(unavailable));
    }
  };

  const rove = (target: HTMLButtonElement | undefined, focus: boolean): void => {
    const all = buttons();
    const current = target ?? all.find((button) => button.tabIndex === 0) ?? all[0];
    for (const button of all) button.tabIndex = button === current ? 0 : -1;
    if (focus) current?.focus();
  };

  const onClick = (event: MouseEvent): void => {
    const button = (event.target as Element | null)?.closest<HTMLButtonElement>("button[data-kotoba-command]");
    if (!button || !toolbar.contains(button)) return;
    event.preventDefault();
    rove(button, false);
    if (button.getAttribute("aria-disabled") === "true") return;

    const command = button.dataset.kotobaCommand;
    if (!isCommand(command)) return;

    if (command === "link") {
      options.onLink();
    } else if (command === "upload") {
      options.onUpload();
    } else {
      runCommand(editor, command, state);
      const item = TOOLBAR_ITEMS.find((entry) => entry.command === command);
      if (item && (TOGGLE_FORMATS.has(command) || BLOCK_COMMANDS.has(command))) {
        const pressed = button.getAttribute("aria-pressed") !== "true";
        options.announce(`${item.label} ${pressed ? "on" : "off"}`);
      }
    }
  };

  // A mouse press on a button keeps the focus (and the selection) in the editor.
  const onMouseDown = (event: MouseEvent): void => {
    if ((event.target as Element | null)?.closest("button[data-kotoba-command]")) event.preventDefault();
  };

  const onKeyDown = (event: KeyboardEvent): void => {
    const all = buttons();
    const index = all.findIndex((button) => button === document.activeElement);
    if (index === -1) return;

    let next: number | null = null;
    if (event.key === "ArrowRight" || event.key === "ArrowDown") next = (index + 1) % all.length;
    if (event.key === "ArrowLeft" || event.key === "ArrowUp") next = (index - 1 + all.length) % all.length;
    if (event.key === "Home") next = 0;
    if (event.key === "End") next = all.length - 1;

    if (next !== null) {
      event.preventDefault();
      rove(all[next], true);
    }
  };

  toolbar.addEventListener("click", onClick);
  toolbar.addEventListener("mousedown", onMouseDown);
  toolbar.addEventListener("keydown", onKeyDown);
  rove(undefined, false);

  const unregister = mergeRegister(
    editor.registerUpdateListener(({ editorState }) => {
      state = editorState.read($readSelectionState);
      refresh();
    }),
    editor.registerCommand(
      CAN_UNDO_COMMAND,
      (canUndo) => {
        history.undo = canUndo;
        refresh();
        return false;
      },
      COMMAND_PRIORITY_LOW,
    ),
    editor.registerCommand(
      CAN_REDO_COMMAND,
      (canRedo) => {
        history.redo = canRedo;
        refresh();
        return false;
      },
      COMMAND_PRIORITY_LOW,
    ),
  );

  refresh();

  return {
    element: toolbar,
    setDisabled(value: boolean) {
      disabled = value;
      refresh();
    },
    dispose() {
      unregister();
      toolbar.removeEventListener("click", onClick);
      toolbar.removeEventListener("mousedown", onMouseDown);
      toolbar.removeEventListener("keydown", onKeyDown);
      if (options.existing === null) toolbar.remove();
    },
  };
}

function buildToolbar(uploads: boolean): HTMLElement {
  const toolbar = document.createElement("div");
  toolbar.dataset.kotobaToolbar = "";
  let group: HTMLElement | null = null;

  for (const item of TOOLBAR_ITEMS) {
    if (item.command === "upload" && !uploads) continue;

    if (group === null || group.dataset.group !== item.group) {
      group = document.createElement("div");
      group.className = "kotoba-toolbar-group";
      group.dataset.group = item.group;
      group.setAttribute("role", "group");
      group.setAttribute("aria-label", item.group);
      toolbar.append(group);
    }

    const button = document.createElement("button");
    button.type = "button";
    button.className = "kotoba-toolbar-button";
    button.dataset.kotobaCommand = item.command;
    button.setAttribute("aria-label", item.label);
    button.title = item.shortcut ? `${item.label} (${item.shortcut})` : item.label;
    button.tabIndex = -1;

    const text = document.createElement("span");
    text.setAttribute("aria-hidden", "true");
    text.textContent = item.text;
    button.append(text);

    group.append(button);
  }

  return toolbar;
}
