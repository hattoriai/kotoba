// The toolbar: a `role="toolbar"` with a roving tabindex (the arrow keys,
// Home and End move between the buttons) and `aria-pressed` on the buttons
// that reflect the selection.
//
// The hook builds the default toolbar. An app can render its own: a
// `[data-kotoba-toolbar]` element inside the hook element (or anywhere, with
// `data-kotoba-toolbar="<hook element id>"`) that holds buttons with a
// `data-kotoba-command` attribute. The commands are the `command` values of
// `TOOLBAR_ITEMS`.
//
// Alt+F10 in the editor moves the focus to the toolbar's tab stop. It is the
// way to the toolbar from a table cell, where Tab and Shift+Tab move between
// the cells.
//
// The table commands other than `table` act on the table at the selection.
// Their buttons (and an element with `data-kotoba-context="table"`, such as
// the default toolbar's Table group) are hidden when the selection is not
// in a table.
//
// `code-language` is a `<select>` (with `data-kotoba-command="code-language"`)
// that sets the language of the code block at the selection. It (and an
// element with `data-kotoba-context="code"`) is hidden when the selection is
// not in a code block. The toolbar fills its options.

import { $createCodeNode, $isCodeNode, type CodeNode } from "@lexical/code-core";
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
  $createTableNodeWithDimensions,
  $deleteTableColumnAtSelection,
  $deleteTableRowAtSelection,
  $findCellNode,
  $findTableNode,
  $insertTableColumnAtSelection,
  $insertTableRowAtSelection,
  $isTableCellNode,
  $isTableRowNode,
  $isTableSelection,
  TableCellHeaderStates,
  type TableCellNode,
  type TableNode,
} from "@lexical/table";
import {
  $createHeadingNode,
  $createQuoteNode,
  $isHeadingNode,
  $isQuoteNode,
  type HeadingTagType,
} from "@lexical/rich-text";
import { $setBlocksType } from "@lexical/selection";
import { $findMatchingParent, $getNearestNodeOfType, $insertNodeToNearestRoot } from "@lexical/utils";
import {
  $createParagraphNode,
  $getSelection,
  $isRangeSelection,
  $isRootOrShadowRoot,
  $setSelection,
  CAN_REDO_COMMAND,
  CAN_UNDO_COMMAND,
  COMMAND_PRIORITY_LOW,
  KEY_DOWN_COMMAND,
  FORMAT_TEXT_COMMAND,
  SKIP_DOM_SELECTION_TAG,
  REDO_COMMAND,
  UNDO_COMMAND,
  mergeRegister,
  type ElementNode,
  type LexicalEditor,
  type TextFormatType,
} from "lexical";

import { CODE_LANGUAGES, type CodeLanguage, PLAIN_TEXT, findCodeLanguage } from "./code_languages";
import { TOOLBAR_ICONS, renderIcon } from "./icons";
import { $domSelection, $selectedLinkUrl } from "./link";

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

/** The table at the selection: whether its first row and first column are header cells. */
export interface TableState {
  headerRow: boolean;
  headerColumn: boolean;
}

export interface SelectionState {
  formats: Set<TextFormatType>;
  block: BlockType;
  link: boolean;
  /** The table at the selection, or `null` when the selection is not in a table. */
  table: TableState | null;
  /**
   * The code block at the selection: its language as it is stored (`null`
   * for none), or `null` when the selection is not in a code block.
   */
  code: { language: string | null } | null;
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
  | "table"
  | "upload"
  | "code-language"
  | "table-row-before"
  | "table-row-after"
  | "table-column-before"
  | "table-column-after"
  | "table-header-row"
  | "table-header-column"
  | "table-delete-row"
  | "table-delete-column"
  | "table-delete"
  | "undo"
  | "redo";

interface ToolbarItem {
  command: ToolbarCommand;
  label: string;
  group: string;
  shortcut?: string;
  /** What the live region says when the command has run (the toggles say "on" or "off"). */
  done?: string;
}

const MOD = typeof navigator !== "undefined" && /Mac|iP(hone|ad)/.test(navigator.platform) ? "⌘" : "Ctrl+";

export const TOOLBAR_ITEMS: readonly ToolbarItem[] = [
  { command: "bold", label: "Bold", group: "Text", shortcut: `${MOD}B` },
  { command: "italic", label: "Italic", group: "Text", shortcut: `${MOD}I` },
  { command: "strikethrough", label: "Strikethrough", group: "Text" },
  { command: "code", label: "Inline code", group: "Text" },
  { command: "link", label: "Link", group: "Text", shortcut: `${MOD}K` },
  { command: "h1", label: "Heading 1", group: "Blocks" },
  { command: "h2", label: "Heading 2", group: "Blocks" },
  { command: "h3", label: "Heading 3", group: "Blocks" },
  { command: "h4", label: "Heading 4", group: "Blocks" },
  { command: "quote", label: "Quote", group: "Blocks" },
  { command: "bullet", label: "Bulleted list", group: "Lists" },
  { command: "number", label: "Numbered list", group: "Lists" },
  { command: "check", label: "Check list", group: "Lists" },
  { command: "code-block", label: "Code block", group: "Insert" },
  { command: "rule", label: "Horizontal rule", group: "Insert" },
  { command: "table", label: "Table", group: "Insert", done: "Table inserted" },
  { command: "upload", label: "Attach a file", group: "Insert" },
  { command: "code-language", label: "Code language", group: "Code" },
  { command: "table-row-before", label: "Insert row above", group: "Table", done: "Row inserted" },
  { command: "table-row-after", label: "Insert row below", group: "Table", done: "Row inserted" },
  { command: "table-column-before", label: "Insert column before", group: "Table", done: "Column inserted" },
  { command: "table-column-after", label: "Insert column after", group: "Table", done: "Column inserted" },
  { command: "table-header-row", label: "Header row", group: "Table" },
  { command: "table-header-column", label: "Header column", group: "Table" },
  { command: "table-delete-row", label: "Delete row", group: "Table", done: "Row deleted" },
  { command: "table-delete-column", label: "Delete column", group: "Table", done: "Column deleted" },
  { command: "table-delete", label: "Delete table", group: "Table", done: "Table deleted" },
  { command: "undo", label: "Undo", group: "History", shortcut: `${MOD}Z` },
  { command: "redo", label: "Redo", group: "History" },
];

const COMMANDS = new Set<string>(TOOLBAR_ITEMS.map((item) => item.command));
const TOGGLE_FORMATS = new Set<string>(["bold", "italic", "strikethrough", "code"]);
const BLOCK_COMMANDS = new Set<string>(["h1", "h2", "h3", "h4", "quote", "bullet", "number", "check", "code-block"]);
/** The commands that act on the table at the selection. */
const TABLE_COMMANDS = new Set<string>(
  TOOLBAR_ITEMS.filter((item) => item.group === "Table").map((item) => item.command),
);
const TABLE_TOGGLES = new Set<string>(["table-header-row", "table-header-column"]);

/** The rows and columns of a new table. */
export const NEW_TABLE_ROWS = 3;
export const NEW_TABLE_COLUMNS = 3;

/** The commands that are a `<select>`, not a button. */
const SELECT_COMMANDS = new Set<string>(["code-language"]);

function isCommand(value: string | undefined): value is ToolbarCommand {
  return value !== undefined && COMMANDS.has(value);
}

function $firstCells(table: TableNode): { row: TableCellNode[]; column: TableCellNode[] } {
  const rows = table.getChildren().filter($isTableRowNode);
  const cells = (row: (typeof rows)[number]) => row.getChildren().filter($isTableCellNode);
  return {
    row: rows.length > 0 ? cells(rows[0]) : [],
    column: rows.flatMap((row) => cells(row).slice(0, 1)),
  };
}

function $readTableState(table: TableNode): TableState {
  const { row, column } = $firstCells(table);
  const all = (cells: TableCellNode[], state: number) =>
    cells.length > 0 && cells.every((cell) => cell.hasHeaderState(state));
  return {
    headerRow: all(row, TableCellHeaderStates.ROW),
    headerColumn: all(column, TableCellHeaderStates.COLUMN),
  };
}

/** The table at the selection: a caret or a range in a cell, or selected cells. */
function $selectedTable(): TableNode | null {
  const selection = $getSelection();
  if ($isTableSelection(selection)) return $findTableNode(selection.anchor.getNode());
  if (!$isRangeSelection(selection)) return null;
  const cell = $findCellNode(selection.anchor.getNode());
  return cell === null ? null : $findTableNode(cell);
}

/** The code block at the anchor of the selection. */
function $selectedCodeNode(): CodeNode | null {
  const selection = $getSelection();
  if (!$isRangeSelection(selection)) return null;
  return $findMatchingParent(selection.anchor.getNode(), $isCodeNode) as CodeNode | null;
}

/**
 * Sets the language of the code block at the selection: an id of
 * `CODE_LANGUAGES`, or `PLAIN_TEXT.id` for none.
 */
export function $setCodeLanguage(id: string): void {
  const code = $selectedCodeNode();
  if (code === null) return;
  code.setLanguage(id === PLAIN_TEXT.id ? undefined : id);
}

/** Reads the formats, the block type, the link, the table and the code block at the selection. */
export function $readSelectionState(): SelectionState {
  const state: SelectionState = { formats: new Set(), block: "paragraph", link: false, table: null, code: null };
  const table = $selectedTable();
  if (table !== null) state.table = $readTableState(table);

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

  const code = $selectedCodeNode();
  if (code !== null) state.code = { language: code.getLanguage() ?? null };
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
    case "table":
      editor.update($insertTable);
      return;
    case "table-row-before":
    case "table-row-after":
    case "table-column-before":
    case "table-column-after":
    case "table-header-row":
    case "table-header-column":
    case "table-delete-row":
    case "table-delete-column":
    case "table-delete":
      editor.update(() => $runTableCommand(command, state));
      return;
    case "undo":
      editor.dispatchCommand(UNDO_COMMAND, undefined);
      return;
    case "redo":
      editor.dispatchCommand(REDO_COMMAND, undefined);
      return;
    case "link":
    case "upload":
    case "code-language":
      return;
  }
}

/**
 * Inserts a table with a header row at the selection, and puts the caret in
 * its first cell. There is no table in a table.
 *
 * A paragraph follows the table, so there is a place to write after it.
 * It also keeps a click in another cell working: Lexical drops the click of
 * a document that is one table with the caret in an empty cell (its
 * "single empty block" case).
 */
function $insertTable(): void {
  const selection = $getSelection();
  if (!$isRangeSelection(selection) || $findTableNode(selection.anchor.getNode()) !== null) return;

  const table = $createTableNodeWithDimensions(NEW_TABLE_ROWS, NEW_TABLE_COLUMNS, { rows: true, columns: false });
  $insertNodeToNearestRoot(table);
  if (table.getNextSibling() === null) table.insertAfter($createParagraphNode());
  table.getFirstDescendant()?.selectStart();
}

function $runTableCommand(command: ToolbarCommand, state: SelectionState): void {
  const table = $selectedTable();
  if (table === null || state.table === null) return;

  switch (command) {
    case "table-row-before":
    case "table-row-after":
      $insertTableRowAtSelection(command === "table-row-after");
      return;
    case "table-column-before":
    case "table-column-after": {
      // Lexical moves the caret to the new column; it stays where it was,
      // as when a row is inserted.
      const selection = $getSelection();
      const before = selection === null ? null : selection.clone();
      $insertTableColumnAtSelection(command === "table-column-after");
      if (before !== null) $setSelection(before);
      return;
    }
    case "table-delete-row":
      $deleteTableRowAtSelection();
      return;
    case "table-delete-column":
      $deleteTableColumnAtSelection();
      return;
    case "table-header-row":
    case "table-header-column": {
      const row = command === "table-header-row";
      const flag = row ? TableCellHeaderStates.ROW : TableCellHeaderStates.COLUMN;
      const on = row ? !state.table.headerRow : !state.table.headerColumn;
      const { row: firstRow, column: firstColumn } = $firstCells(table);
      for (const cell of row ? firstRow : firstColumn) {
        cell.setHeaderStyles(on ? flag : TableCellHeaderStates.NO_STATUS, flag);
      }
      return;
    }
    case "table-delete": {
      // The caret goes where the table was, in a new empty paragraph.
      const paragraph = $createParagraphNode();
      table.replace(paragraph);
      paragraph.select();
      return;
    }
    default:
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
  /** The languages of the code language picker. The default is every language. */
  codeLanguages?: readonly CodeLanguage[];
}

/** A control of the toolbar: a button, or the `<select>` of `code-language`. */
type Control = HTMLButtonElement | HTMLSelectElement;

/** The value of the picker's option for a language that is not one of the editor's. */
const UNKNOWN_LANGUAGE = "kotoba-unknown-language";

export function createToolbar(editor: LexicalEditor, options: ToolbarOptions): Toolbar {
  const toolbar = options.existing ?? buildToolbar(options.uploads);
  if (options.existing === null) options.host.prepend(toolbar);

  toolbar.setAttribute("role", "toolbar");
  if (!toolbar.hasAttribute("aria-label")) toolbar.setAttribute("aria-label", options.label);
  toolbar.classList.add("kotoba-toolbar");

  const codeLanguages = options.codeLanguages ?? CODE_LANGUAGES;

  // Every control, a hidden one too, and the controls that show.
  const commandButtons = (): Control[] =>
    Array.from(
      toolbar.querySelectorAll<Control>("button[data-kotoba-command], select[data-kotoba-command]"),
    ).filter((control) =>
      control instanceof HTMLSelectElement
        ? SELECT_COMMANDS.has(control.dataset.kotobaCommand ?? "")
        : isCommand(control.dataset.kotobaCommand),
    );
  const buttons = (): Control[] => commandButtons().filter((control) => !control.hidden);

  // The options of the picker: plain text, the editor's languages, the
  // language of the block when the editor does not offer it, and a name that
  // is no language (kept, not highlighted). An alias shows its language, and
  // the block keeps the alias until the person picks a language.
  const fillLanguages = (select: HTMLSelectElement, language: string | null): void => {
    const current = findCodeLanguage(language);
    const offered = [...codeLanguages];
    if (current !== null && current !== PLAIN_TEXT && !offered.includes(current)) offered.push(current);

    const entries: [value: string, label: string][] = [
      [PLAIN_TEXT.id, PLAIN_TEXT.label],
      ...offered.map((entry): [string, string] => [entry.id, entry.label]),
    ];
    if (current === null) entries.push([UNKNOWN_LANGUAGE, `${language ?? ""} (not highlighted)`]);

    // Rebuilt only when the options change, so that an open list stays open.
    const key = entries.map((entry) => entry.join("=")).join("|");
    if (select.dataset.kotobaOptions !== key) {
      select.replaceChildren(...entries.map(([value, label]) => new Option(label, value)));
      select.dataset.kotobaOptions = key;
    }
    select.value = current?.id ?? UNKNOWN_LANGUAGE;
  };

  let state: SelectionState = { formats: new Set(), block: "paragraph", link: false, table: null, code: null };
  let disabled = false;
  const history = { undo: false, redo: false };

  const refresh = (): void => {
    const focused = document.activeElement;
    const inTable = state.table !== null;
    const inCode = state.code !== null;
    for (const element of toolbar.querySelectorAll<HTMLElement>('[data-kotoba-context="table"]')) {
      element.hidden = !inTable;
    }
    for (const element of toolbar.querySelectorAll<HTMLElement>('[data-kotoba-context="code"]')) {
      element.hidden = !inCode;
    }

    for (const button of commandButtons()) {
      const command = button.dataset.kotobaCommand as ToolbarCommand;
      if (TABLE_COMMANDS.has(command)) button.hidden = !inTable;

      if (button instanceof HTMLSelectElement) {
        button.hidden = !inCode;
        if (state.code !== null) fillLanguages(button, state.code.language);
        button.setAttribute("aria-disabled", String(disabled));
        continue;
      }

      if (TABLE_TOGGLES.has(command)) {
        const pressed = command === "table-header-row" ? state.table?.headerRow : state.table?.headerColumn;
        button.setAttribute("aria-pressed", String(pressed === true));
      } else if (TOGGLE_FORMATS.has(command)) {
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
        (command === "upload" && !options.uploads) ||
        (command === "table" && inTable);
      button.setAttribute("aria-disabled", String(unavailable));
    }

    // A table or code control that was just hidden (the selection left the
    // table or the code block, or the table was deleted) gives the focus
    // back to the editor, and the toolbar keeps a tab stop.
    const visible = buttons();
    if (!visible.some((button) => button.tabIndex === 0)) rove(undefined, false);
    const control = focused instanceof HTMLButtonElement || focused instanceof HTMLSelectElement;
    if (control && toolbar.contains(focused) && focused.hidden) editor.focus();
  };

  const rove = (target: Control | undefined, focus: boolean): void => {
    const all = buttons();
    const current = target ?? all.find((button) => button.tabIndex === 0) ?? all[0];
    // Every button, a hidden one too: the toolbar has one tab stop.
    for (const button of commandButtons()) button.tabIndex = button === current ? 0 : -1;
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
    } else if (command === "undo" || command === "redo") {
      runCommand(editor, command, state);
    } else {
      // The DOM selection, when Lexical has not read its last change yet.
      // Lexical then puts the focus back in the editor, with the selection;
      // the toolbar keeps its tab stop on this button.
      editor.update(() => {
        const selection = $domSelection(editor);
        if (selection !== null) $setSelection(selection);
        runCommand(editor, command, $readSelectionState());
      });
    }

    if (command !== "link" && command !== "upload") {
      const item = TOOLBAR_ITEMS.find((entry) => entry.command === command);
      if (item && (TOGGLE_FORMATS.has(command) || BLOCK_COMMANDS.has(command) || TABLE_TOGGLES.has(command))) {
        const pressed = button.getAttribute("aria-pressed") !== "true";
        options.announce(`${item.label} ${pressed ? "on" : "off"}`);
      } else if (item?.done !== undefined) {
        options.announce(item.done);
      }
    }
  };

  // The picker sets the language of the code block at the editor's
  // selection. The focus stays on the picker, so the person can try another
  // language, and the editor does not move the DOM selection.
  const onChange = (event: Event): void => {
    const select = event.target;
    if (!(select instanceof HTMLSelectElement) || !toolbar.contains(select)) return;
    if (select.dataset.kotobaCommand !== "code-language") return;
    rove(select, false);
    if (disabled || select.value === UNKNOWN_LANGUAGE) {
      refresh();
      return;
    }

    const value = select.value;
    editor.update(() => $setCodeLanguage(value), { tag: SKIP_DOM_SELECTION_TAG });
    const label = value === PLAIN_TEXT.id ? PLAIN_TEXT.label : codeLanguages.find((entry) => entry.id === value)?.label;
    options.announce(`Code language ${label ?? value}`);
  };

  // A mouse press on a button keeps the focus (and the selection) in the editor.
  const onMouseDown = (event: MouseEvent): void => {
    if ((event.target as Element | null)?.closest("button[data-kotoba-command]")) event.preventDefault();
  };

  const onKeyDown = (event: KeyboardEvent): void => {
    const all = buttons();
    const index = all.findIndex((button) => button === document.activeElement);
    if (index === -1) return;

    // Up and Down choose an option of a select; Left and Right move on.
    const vertical = !(all[index] instanceof HTMLSelectElement);
    let next: number | null = null;
    if (event.key === "ArrowRight" || (vertical && event.key === "ArrowDown")) next = (index + 1) % all.length;
    if (event.key === "ArrowLeft" || (vertical && event.key === "ArrowUp")) next = (index - 1 + all.length) % all.length;
    if (event.key === "Home") next = 0;
    if (event.key === "End") next = all.length - 1;

    if (next !== null) {
      event.preventDefault();
      rove(all[next], true);
    }
  };

  toolbar.addEventListener("click", onClick);
  toolbar.addEventListener("change", onChange);
  toolbar.addEventListener("mousedown", onMouseDown);
  toolbar.addEventListener("keydown", onKeyDown);
  rove(undefined, false);

  const unregister = mergeRegister(
    editor.registerUpdateListener(({ editorState }) => {
      state = editorState.read($readSelectionState);
      refresh();
    }),
    editor.registerCommand(
      KEY_DOWN_COMMAND,
      (event: KeyboardEvent) => {
        if (!event.altKey || event.key !== "F10" || event.ctrlKey || event.metaKey || event.shiftKey) return false;
        if (buttons().length === 0) return false;
        event.preventDefault();
        rove(undefined, true);
        return true;
      },
      COMMAND_PRIORITY_LOW,
    ),
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
      toolbar.removeEventListener("change", onChange);
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
      if (TABLE_COMMANDS.has(item.command)) {
        group.dataset.kotobaContext = "table";
        group.hidden = true;
      } else if (SELECT_COMMANDS.has(item.command)) {
        group.dataset.kotobaContext = "code";
        group.hidden = true;
      }
      toolbar.append(group);
    }

    if (SELECT_COMMANDS.has(item.command)) {
      const select = document.createElement("select");
      select.className = "kotoba-toolbar-select";
      select.dataset.kotobaCommand = item.command;
      select.setAttribute("aria-label", item.label);
      select.title = item.label;
      select.tabIndex = -1;
      select.hidden = true;
      group.append(select);
      continue;
    }

    const button = document.createElement("button");
    button.type = "button";
    button.className = "kotoba-toolbar-button";
    button.dataset.kotobaCommand = item.command;
    button.setAttribute("aria-label", item.label);
    button.title = item.shortcut ? `${item.label} (${item.shortcut})` : item.label;
    button.tabIndex = -1;

    button.append(renderIcon(TOOLBAR_ICONS[item.command as Exclude<ToolbarCommand, "code-language">]));

    group.append(button);
  }

  return toolbar;
}
