// The prompt menu. A trigger character (for example "@"), typed at the start
// of a line or after a space, opens a listbox under the caret. The text
// after the trigger is the query. The arrow keys move the active option
// (`aria-activedescendant` on the editable element), Enter or Tab inserts
// the active result, and Escape closes the menu.
//
// Each prompt has options (`data-prompt-config`, see `Kotoba.Prompts`):
//
//   * `spaces` lets the query have spaces: it then ends at two spaces in a
//     row, and cannot start with a space;
//   * `minLength` and `maxLength` bound the query;
//   * `items` makes the prompt local: the editor filters its items, with no
//     request. Otherwise the hook sends the query to the server, which
//     answers with the results; the editor keeps the answers of the menu's
//     queries, drops an answer to an older query, and gives up on a query
//     with no answer after a while;
//   * `insert` is what a result inserts: a mention (the default), text, or a
//     node of the editor (`nodeType`, from the item's `attrs`).

import { $isCodeHighlightNode, $isCodeNode } from "@lexical/code-core";
import {
  $createTextNode,
  $getNodeByKey,
  $isRangeSelection,
  $getSelection,
  $isTextNode,
  $parseSerializedNode,
  COMMAND_PRIORITY_HIGH,
  KEY_ARROW_DOWN_COMMAND,
  KEY_ARROW_UP_COMMAND,
  KEY_ENTER_COMMAND,
  KEY_ESCAPE_COMMAND,
  KEY_TAB_COMMAND,
  mergeRegister,
  type LexicalEditor,
  type LexicalNode,
  type NodeKey,
  type SerializedLexicalNode,
} from "lexical";

import { position } from "./link";
import { $createMentionNode } from "./nodes/mention";
import { isObject } from "./protocol";

export interface PromptItem {
  id: string;
  label: string;
  hint?: string;
  /** What an `insert: :text` prompt inserts; the label when there is none. */
  text?: string;
  /** The attributes of the node that an `insert: {:node, type}` prompt inserts. */
  attrs?: Record<string, unknown>;
}

export interface PromptConfig {
  spaces: boolean;
  minLength: number;
  maxLength: number;
  insert: "mention" | "text" | "node";
  nodeType: string | null;
  /** The items of a local prompt, or `null` for a prompt that the server answers. */
  items: PromptItem[] | null;
}

interface Match {
  prompt: string;
  trigger: string;
  query: string;
  nodeKey: NodeKey;
  start: number;
  end: number;
}

export interface Prompts {
  receive(prompt: string, items: unknown, query?: unknown, error?: unknown): void;
  close(): void;
  dispose(): void;
}

interface PromptOptions {
  host: HTMLElement;
  editable: HTMLElement;
  idPrefix: string;
  /** Trigger character → prompt name. */
  triggers: ReadonlyMap<string, string>;
  /** Prompt name → accessible name of its menu, for the prompts that have one. */
  labels: ReadonlyMap<string, string>;
  /** Prompt name → its options, for the prompts that have some. */
  configs?: ReadonlyMap<string, PromptConfig>;
  request(prompt: string, query: string): void;
  announce(message: string): void;
}

const MAX_QUERY = 64;
const MAX_QUERY_LIMIT = 200;
const MAX_ITEMS = 50;
const MAX_LOCAL_ITEMS = 500;
const REQUEST_DELAY = 120;
/** A query with no answer after this long gives "Results did not load". */
export const REQUEST_TIMEOUT = 8000;

export const DEFAULT_CONFIG: PromptConfig = {
  spaces: false,
  minLength: 0,
  maxLength: MAX_QUERY,
  insert: "mention",
  nodeType: null,
  items: null,
};

function parseObject(json: string | undefined, attribute: string): Record<string, unknown> | null {
  if (json === undefined || json.trim() === "") return null;
  try {
    const data: unknown = JSON.parse(json);
    return isObject(data) ? data : null;
  } catch {
    console.error(`Kotoba: ${attribute} is not valid JSON`);
    return null;
  }
}

/** Reads the `data-prompts` JSON: an object of trigger character → prompt name. */
export function parseTriggers(json: string | undefined): Map<string, string> {
  const triggers = new Map<string, string>();
  for (const [trigger, prompt] of Object.entries(parseObject(json, "data-prompts") ?? {})) {
    if ([...trigger].length !== 1 || /\s/.test(trigger) || typeof prompt !== "string") {
      console.error(`Kotoba: the prompt trigger ${JSON.stringify(trigger)} must be one character`);
      continue;
    }
    triggers.set(trigger, prompt);
  }
  return triggers;
}

/** Reads the `data-prompt-labels` JSON: an object of prompt name → label. */
export function parseLabels(json: string | undefined): Map<string, string> {
  const labels = new Map<string, string>();
  for (const [prompt, label] of Object.entries(parseObject(json, "data-prompt-labels") ?? {})) {
    if (typeof label === "string" && label.trim() !== "") labels.set(prompt, label);
  }
  return labels;
}

const integerIn = (value: unknown, min: number, max: number, fallback: number): number =>
  typeof value === "number" && Number.isInteger(value) && value >= min && value <= max ? value : fallback;

/** Reads the `data-prompt-config` JSON: an object of prompt name → options. */
export function parseConfigs(json: string | undefined): Map<string, PromptConfig> {
  const configs = new Map<string, PromptConfig>();
  for (const [prompt, value] of Object.entries(parseObject(json, "data-prompt-config") ?? {})) {
    if (!isObject(value)) continue;
    const maxLength = integerIn(value.maxLength, 1, MAX_QUERY_LIMIT, MAX_QUERY);
    const insert = value.insert === "text" || value.insert === "node" ? value.insert : "mention";
    const nodeType = typeof value.nodeType === "string" && value.nodeType !== "" ? value.nodeType : null;
    if (insert === "node" && nodeType === null) {
      console.error(`Kotoba: the prompt "${prompt}" inserts a node with no type`);
      continue;
    }
    configs.set(prompt, {
      spaces: value.spaces === true,
      minLength: integerIn(value.minLength, 0, maxLength, 0),
      maxLength,
      insert,
      nodeType,
      items: Array.isArray(value.items) ? readItems(value.items, MAX_LOCAL_ITEMS) : null,
    });
  }
  return configs;
}

/** Reads result items, and drops the ones that are not valid. */
export function readItems(items: unknown, max = MAX_ITEMS): PromptItem[] {
  if (!Array.isArray(items)) return [];
  const valid: PromptItem[] = [];

  for (const item of items) {
    if (!isObject(item)) continue;
    const { id, label, hint, text, attrs } = item;
    if ((typeof id !== "string" && typeof id !== "number") || typeof label !== "string") continue;
    const read: PromptItem = { id: String(id), label };
    if (typeof hint === "string") read.hint = hint;
    if (typeof text === "string" && text !== "") read.text = text;
    if (isObject(attrs)) read.attrs = attrs;
    valid.push(read);
    if (valid.length === max) break;
  }
  return valid;
}

// Lower case, with no accents: "Álvarez" → "alvarez".
const fold = (text: string): string => text.normalize("NFD").replace(/\p{Mn}/gu, "").toLowerCase();
const words = (text: string): string[] => fold(text).split(/[^\p{L}\p{N}]+/u).filter((word) => word !== "");

/**
 * Filters the items of a local prompt, as `Kotoba.Prompts.filter/2` does:
 * each word of the query must start a word of the label or the hint. The
 * items whose label starts with the query come first.
 */
export function filterItems(items: readonly PromptItem[], query: string): PromptItem[] {
  const wanted = words(query);
  const folded = fold(query);
  const matches = items.filter((item) => {
    const haystack = words(`${item.label} ${item.hint ?? ""}`);
    return wanted.every((word) => haystack.some((candidate) => candidate.startsWith(word)));
  });
  const first = matches.filter((item) => fold(item.label).startsWith(folded));
  const rest = matches.filter((item) => !fold(item.label).startsWith(folded));
  return [...first, ...rest].slice(0, MAX_ITEMS);
}

/**
 * The query that a prompt accepts: no white space without `spaces`; with
 * it, no white space first and no two in a row. At most `maxLength`.
 */
export function acceptsQuery(query: string, config: PromptConfig): boolean {
  if ([...query].length > config.maxLength) return false;
  if (!config.spaces) return !/\s/.test(query);
  return !/^\s/.test(query) && !/\s\s/.test(query);
}

function $findMatch(triggers: ReadonlyMap<string, string>, configOf: (prompt: string) => PromptConfig): Match | null {
  const selection = $getSelection();
  if (!$isRangeSelection(selection) || !selection.isCollapsed()) return null;

  const node = selection.anchor.getNode();
  if (!$isTextNode(node) || $isCodeHighlightNode(node) || $isCodeNode(node.getParent())) return null;
  if (!node.isSimpleText()) return null;

  const end = selection.anchor.offset;
  const text = node.getTextContent().slice(0, end);

  // Back from the caret to the nearest trigger at the start of the text or
  // after white space. Two white space characters in a row end every query.
  for (let index = text.length - 1; index >= 0 && text.length - index <= MAX_QUERY_LIMIT + 1; index -= 1) {
    const char = text.charAt(index);
    if (/\s/.test(char) && index > 0 && /\s/.test(text.charAt(index - 1))) return null;
    const prompt = triggers.get(char);
    if (prompt === undefined) continue;
    if (index > 0 && !/\s/.test(text.charAt(index - 1))) continue;
    const query = text.slice(index + 1);
    if (!acceptsQuery(query, configOf(prompt))) return null;
    return { prompt, trigger: char, query, nodeKey: node.getKey(), start: index, end };
  }
  return null;
}

type Status = "idle" | "loading" | "failed" | "short";

/** The text that a query searches for: with no white space at its end ("Ada " searches "Ada"). */
export const searchTerm = (query: string): string => query.replace(/\s+$/u, "");

export function createPrompts(editor: LexicalEditor, options: PromptOptions): Prompts {
  const configOf = (prompt: string): PromptConfig => options.configs?.get(prompt) ?? DEFAULT_CONFIG;

  const menu = document.createElement("div");
  menu.className = "kotoba-menu";
  menu.hidden = true;

  const listbox = document.createElement("ul");
  listbox.id = `${options.idPrefix}-menu`;
  listbox.className = "kotoba-menu-list";
  listbox.setAttribute("role", "listbox");

  const status = document.createElement("div");
  status.className = "kotoba-menu-status";

  menu.append(listbox, status);
  options.host.append(menu);

  const { editable } = options;
  editable.setAttribute("aria-autocomplete", "list");
  editable.setAttribute("aria-controls", listbox.id);

  let match: Match | null = null;
  let items: PromptItem[] = [];
  let active = 0;
  let state: Status = "idle";
  let dismissed: string | null = null;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let timeout: ReturnType<typeof setTimeout> | undefined;
  // The server's answers while the menu is open: prompt + query → items.
  const answers = new Map<string, PromptItem[]>();

  const matchId = (m: Match): string => `${m.nodeKey}:${m.start}`;
  const optionId = (index: number): string => `${options.idPrefix}-option-${index}`;
  const answerKey = (prompt: string, query: string): string => `${prompt}\u0000${query}`;

  const statusText = (): string => {
    if (state === "loading") return "Searching…";
    if (state === "failed") return "Results did not load";
    if (state === "short") return "Keep typing to search";
    return items.length === 0 ? "No results" : "";
  };

  const render = (): void => {
    if (match === null) {
      menu.hidden = true;
      editable.removeAttribute("aria-activedescendant");
      return;
    }

    listbox.setAttribute("aria-label", options.labels.get(match.prompt) ?? `${match.prompt} suggestions`);
    listbox.replaceChildren(
      ...items.map((item, index) => {
        const option = document.createElement("li");
        option.id = optionId(index);
        option.className = "kotoba-menu-option";
        option.setAttribute("role", "option");
        option.setAttribute("aria-selected", String(index === active));

        const label = document.createElement("span");
        label.className = "kotoba-menu-label";
        label.textContent = item.label;
        option.append(label);

        if (item.hint !== undefined) {
          const hint = document.createElement("span");
          hint.className = "kotoba-menu-hint";
          hint.textContent = item.hint;
          option.append(hint);
        }
        return option;
      }),
    );

    status.textContent = statusText();
    status.hidden = status.textContent === "";
    listbox.hidden = items.length === 0;

    const wasHidden = menu.hidden;
    menu.hidden = false;
    if (wasHidden) position(menu, options.host);

    if (items.length > 0) {
      editable.setAttribute("aria-activedescendant", optionId(active));
      document.getElementById(optionId(active))?.scrollIntoView({ block: "nearest" });
    } else {
      editable.removeAttribute("aria-activedescendant");
    }
  };

  const announceResults = (): void => {
    if (state === "failed") options.announce("Results did not load");
    else options.announce(items.length === 0 ? "No results" : items.length === 1 ? "1 result" : `${items.length} results`);
  };

  const stopTimers = (): void => {
    clearTimeout(timer);
    clearTimeout(timeout);
  };

  const close = (): void => {
    stopTimers();
    match = null;
    items = [];
    state = "idle";
    answers.clear();
    render();
  };

  // Shows the results of a query: local, a kept answer, or a request.
  const search = (next: Match): void => {
    stopTimers();
    const config = configOf(next.prompt);
    const term = searchTerm(next.query);

    if ([...term].length < config.minLength) {
      items = [];
      state = "short";
      return;
    }
    if (config.items !== null) {
      items = filterItems(config.items, term);
      state = "idle";
      announceResults();
      return;
    }
    const answer = answers.get(answerKey(next.prompt, term));
    if (answer !== undefined) {
      items = answer;
      state = "idle";
      announceResults();
      return;
    }

    state = "loading";
    timer = setTimeout(() => options.request(next.prompt, term), REQUEST_DELAY);
    timeout = setTimeout(() => {
      if (match === null || state !== "loading" || searchTerm(match.query) !== term) return;
      items = [];
      state = "failed";
      render();
      announceResults();
    }, REQUEST_DELAY + REQUEST_TIMEOUT);
  };

  // Builds the node of an `insert: node` prompt. It throws when the editor
  // does not have the type, or the attributes do not make a node.
  const $createPromptNode = (config: PromptConfig, item: PromptItem): LexicalNode =>
    $parseSerializedNode({ ...item.attrs, type: config.nodeType ?? "", version: 1 } as SerializedLexicalNode);

  const select = (index: number): boolean => {
    const current = match;
    const item = items[index];
    if (current === null || item === undefined) return false;
    const config = configOf(current.prompt);

    // The update can run after this function (in a command, Lexical runs it
    // at the end of the command's update), so it says what it did.
    editor.update(() => {
      const node = $getNodeByKey(current.nodeKey);
      if (!$isTextNode(node)) return;

      let created: LexicalNode;
      if (config.insert === "text") {
        node.select(current.start, current.end).insertText(`${item.text ?? item.label} `);
        options.announce(`Inserted ${item.label}`);
        return;
      } else if (config.insert === "node") {
        try {
          created = $createPromptNode(config, item);
        } catch (error) {
          console.error(`Kotoba: the prompt "${current.prompt}" could not make a ${config.nodeType} node`, error);
          options.announce(`Could not insert ${item.label}`);
          return;
        }
      } else {
        created = $createMentionNode({ kind: current.prompt, id: item.id, label: item.label });
      }

      const selection = node.select(current.start, current.end);
      selection.insertNodes([created]);
      if (created.isInline()) {
        const space = $createTextNode(" ");
        created.insertAfter(space);
        space.select(1, 1);
      }
      options.announce(`Inserted ${item.label}`);
    });

    close();
    return true;
  };

  const onUpdate = (): void => {
    const next = editor.getEditorState().read(() => $findMatch(options.triggers, configOf));

    if (next === null) {
      dismissed = null;
      if (match !== null) close();
      return;
    }
    if (dismissed === matchId(next)) return;

    const opened = match === null || matchId(match) !== matchId(next);
    const changed = opened || searchTerm(match?.query ?? "") !== searchTerm(next.query);
    if (opened) answers.clear();
    match = next;
    if (changed) {
      active = 0;
      search(next);
    }
    render();
  };

  const onMenuMouseDown = (event: MouseEvent): void => event.preventDefault();

  const onMenuClick = (event: MouseEvent): void => {
    const option = (event.target as Element | null)?.closest<HTMLElement>("[role=option]");
    if (!option) return;
    const index = Array.from(listbox.children).indexOf(option);
    if (index >= 0) select(index);
  };

  menu.addEventListener("mousedown", onMenuMouseDown);
  menu.addEventListener("click", onMenuClick);

  const whenOpen =
    (handler: (event: KeyboardEvent) => boolean) =>
    (event: KeyboardEvent | null): boolean => {
      if (match === null || event === null) return false;
      const handled = handler(event);
      if (handled) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
      return handled;
    };

  const move = (step: number) =>
    whenOpen(() => {
      if (items.length === 0) return false;
      active = (active + step + items.length) % items.length;
      render();
      return true;
    });

  const unregister = mergeRegister(
    editor.registerUpdateListener(onUpdate),
    editor.registerCommand(KEY_ARROW_DOWN_COMMAND, move(1), COMMAND_PRIORITY_HIGH),
    editor.registerCommand(KEY_ARROW_UP_COMMAND, move(-1), COMMAND_PRIORITY_HIGH),
    editor.registerCommand(KEY_ENTER_COMMAND, whenOpen(() => select(active)), COMMAND_PRIORITY_HIGH),
    editor.registerCommand(KEY_TAB_COMMAND, whenOpen(() => select(active)), COMMAND_PRIORITY_HIGH),
    editor.registerCommand(
      KEY_ESCAPE_COMMAND,
      whenOpen(() => {
        if (match !== null) dismissed = matchId(match);
        close();
        return true;
      }),
      COMMAND_PRIORITY_HIGH,
    ),
  );

  return {
    receive(prompt: string, results: unknown, query?: unknown, error?: unknown) {
      if (match === null || match.prompt !== prompt || configOf(prompt).items !== null) return;
      const failed = error === true;
      const read = readItems(results);
      // An answer to another query of the menu is kept for later, and does
      // not change the results.
      if (typeof query === "string") {
        if (!failed) answers.set(answerKey(prompt, query), read);
        if (query !== searchTerm(match.query)) return;
      }
      clearTimeout(timeout);
      items = failed ? [] : read;
      active = 0;
      state = failed ? "failed" : "idle";
      render();
      announceResults();
    },
    close,
    dispose() {
      stopTimers();
      unregister();
      menu.removeEventListener("mousedown", onMenuMouseDown);
      menu.removeEventListener("click", onMenuClick);
      menu.remove();
      for (const name of ["aria-autocomplete", "aria-controls", "aria-activedescendant"]) {
        editable.removeAttribute(name);
      }
    },
  };
}
