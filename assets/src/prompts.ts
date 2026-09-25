// The prompt menu. A trigger character (for example "@"), typed at the start
// of a line or after a space, opens a listbox under the caret. The text
// after the trigger is the query: the hook sends it to the server, and the
// server answers with the results. The arrow keys move the active option
// (`aria-activedescendant` on the editable element), Enter or Tab inserts a
// mention, and Escape closes the menu.

import { $isCodeHighlightNode, $isCodeNode } from "@lexical/code-core";
import {
  $createTextNode,
  $getNodeByKey,
  $getSelection,
  $isRangeSelection,
  $isTextNode,
  COMMAND_PRIORITY_HIGH,
  KEY_ARROW_DOWN_COMMAND,
  KEY_ARROW_UP_COMMAND,
  KEY_ENTER_COMMAND,
  KEY_ESCAPE_COMMAND,
  KEY_TAB_COMMAND,
  mergeRegister,
  type LexicalEditor,
  type NodeKey,
} from "lexical";

import { position } from "./link";
import { $createMentionNode } from "./nodes/mention";
import { isObject } from "./protocol";

export interface PromptItem {
  id: string;
  label: string;
  hint?: string;
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
  receive(prompt: string, items: unknown, query?: unknown): void;
  close(): void;
  dispose(): void;
}

interface PromptOptions {
  host: HTMLElement;
  editable: HTMLElement;
  idPrefix: string;
  /** Trigger character → prompt name. */
  triggers: ReadonlyMap<string, string>;
  request(prompt: string, query: string): void;
  announce(message: string): void;
}

const MAX_QUERY = 64;
const MAX_ITEMS = 50;
const REQUEST_DELAY = 120;

/** Reads the `data-prompts` JSON: an object of trigger character → prompt name. */
export function parseTriggers(json: string | undefined): Map<string, string> {
  const triggers = new Map<string, string>();
  if (json === undefined || json.trim() === "") return triggers;

  let data: unknown;
  try {
    data = JSON.parse(json);
  } catch {
    console.error("Kotoba: data-prompts is not valid JSON");
    return triggers;
  }
  if (!isObject(data)) return triggers;

  for (const [trigger, prompt] of Object.entries(data)) {
    if ([...trigger].length !== 1 || /\s/.test(trigger) || typeof prompt !== "string") {
      console.error(`Kotoba: the prompt trigger ${JSON.stringify(trigger)} must be one character`);
      continue;
    }
    triggers.set(trigger, prompt);
  }
  return triggers;
}

/** Reads the result items from the server, and drops the ones that are not valid. */
export function readItems(items: unknown): PromptItem[] {
  if (!Array.isArray(items)) return [];
  const valid: PromptItem[] = [];

  for (const item of items) {
    if (!isObject(item)) continue;
    const { id, label, hint } = item;
    if ((typeof id !== "string" && typeof id !== "number") || typeof label !== "string") continue;
    valid.push(typeof hint === "string" ? { id: String(id), label, hint } : { id: String(id), label });
    if (valid.length === MAX_ITEMS) break;
  }
  return valid;
}

function $findMatch(triggers: ReadonlyMap<string, string>): Match | null {
  const selection = $getSelection();
  if (!$isRangeSelection(selection) || !selection.isCollapsed()) return null;

  const node = selection.anchor.getNode();
  if (!$isTextNode(node) || $isCodeHighlightNode(node) || $isCodeNode(node.getParent())) return null;
  if (!node.isSimpleText()) return null;

  const end = selection.anchor.offset;
  const text = node.getTextContent().slice(0, end);

  for (let index = text.length - 1; index >= 0 && text.length - index <= MAX_QUERY + 1; index -= 1) {
    const char = text.charAt(index);
    if (/\s/.test(char)) return null;
    const prompt = triggers.get(char);
    if (prompt === undefined) continue;
    if (index > 0 && !/\s/.test(text.charAt(index - 1))) continue;
    return { prompt, trigger: char, query: text.slice(index + 1), nodeKey: node.getKey(), start: index, end };
  }
  return null;
}

export function createPrompts(editor: LexicalEditor, options: PromptOptions): Prompts {
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
  let loading = false;
  let dismissed: string | null = null;
  let timer: ReturnType<typeof setTimeout> | undefined;

  const matchId = (m: Match): string => `${m.nodeKey}:${m.start}`;
  const optionId = (index: number): string => `${options.idPrefix}-option-${index}`;

  const render = (): void => {
    if (match === null) {
      menu.hidden = true;
      editable.removeAttribute("aria-activedescendant");
      return;
    }

    listbox.setAttribute("aria-label", `${match.prompt} suggestions`);
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

    status.textContent = loading ? "Searching…" : items.length === 0 ? "No results" : "";
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

  const close = (): void => {
    clearTimeout(timer);
    match = null;
    items = [];
    loading = false;
    render();
  };

  const request = (next: Match): void => {
    clearTimeout(timer);
    loading = true;
    timer = setTimeout(() => options.request(next.prompt, next.query), REQUEST_DELAY);
  };

  const select = (index: number): boolean => {
    const current = match;
    const item = items[index];
    if (current === null || item === undefined) return false;

    editor.update(() => {
      const node = $getNodeByKey(current.nodeKey);
      if (!$isTextNode(node)) return;
      const selection = node.select(current.start, current.end);
      const mention = $createMentionNode({ kind: current.prompt, id: item.id, label: item.label });
      selection.insertNodes([mention]);
      const space = $createTextNode(" ");
      mention.insertAfter(space);
      space.select(1, 1);
    });

    options.announce(`Inserted ${item.label}`);
    close();
    return true;
  };

  const onUpdate = (): void => {
    const next = editor.getEditorState().read(() => $findMatch(options.triggers));

    if (next === null) {
      dismissed = null;
      if (match !== null) close();
      return;
    }
    if (dismissed === matchId(next)) return;

    const changed = match === null || matchId(match) !== matchId(next) || match.query !== next.query;
    match = next;
    if (changed) {
      active = 0;
      request(next);
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
    receive(prompt: string, results: unknown, query?: unknown) {
      if (match === null || match.prompt !== prompt) return;
      if (typeof query === "string" && query !== match.query) return;
      items = readItems(results);
      active = 0;
      loading = false;
      render();
      options.announce(
        items.length === 0 ? "No results" : items.length === 1 ? "1 result" : `${items.length} results`,
      );
    },
    close,
    dispose() {
      clearTimeout(timer);
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
