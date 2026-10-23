// The insert menu: a prompt with `insert: :command` (see prompts.ts and
// `Kotoba.Prompts`). Typed at the start of a line or after a space, its
// trigger ("/") opens a menu of what the field can insert or turn the block
// into, filtered as the person types (`/h2`, `/table`).
//
// An item runs a command on the block of the caret, after the trigger and
// the query are removed, in the same update (one undo step):
//
//   * a block of text ("paragraph", "h1" to "h4", "quote", "bullet",
//     "number", "check", "code-block", or an extension's block,
//     `ext:<type>`): an empty paragraph turns into it; a block with text
//     gets it below (or turns into it, with `withText: "turn_into"`);
//   * "table" and "rule": a block in place of an empty paragraph, else
//     below the block;
//   * "upload" and "embed": the file chooser, the app's embed picker;
//   * an extension's insert item (`<extension>:<command>`): its `run`;
//   * an item with a `node`: that node (a block below, or in place of an
//     empty paragraph; an inline node at the caret), and with `text`, text.
//
// An item of a feature that the editor does not have, or a node of a type
// that it does not have, is left out of the menu.

import { $createHorizontalRuleNode } from "@lexical/extension";
import { $createTableNodeWithDimensions } from "@lexical/table";
import {
  $createParagraphNode,
  $getSelection,
  $isElementNode,
  $isParagraphNode,
  $isRangeSelection,
  $parseSerializedNode,
  type LexicalEditor,
  type LexicalNode,
  type SerializedLexicalNode,
} from "lexical";

import { $caretBlock, $turnInto, turnIntoTargets, type Target } from "./blocks";
import type { InsertControl, KotobaExtension } from "./extensions";
import type { Feature } from "./features";
import { EMBED_ICONS, TOOLBAR_ICONS, renderIcon, type, type Icon } from "./icons";
import type { PromptItem } from "./prompts";
import { NEW_TABLE_COLUMNS, NEW_TABLE_ROWS } from "./toolbar";

/** The feature of each built-in command that is not a block of text. */
const INSERT_FEATURES: Readonly<Record<string, Feature>> = {
  table: "tables",
  rule: "horizontal_rules",
  upload: "attachments",
  embed: "embeds",
};

const ICONS: Readonly<Record<string, Icon>> = {
  paragraph: type,
  h1: TOOLBAR_ICONS.h1,
  h2: TOOLBAR_ICONS.h2,
  h3: TOOLBAR_ICONS.h3,
  h4: TOOLBAR_ICONS.h4,
  quote: TOOLBAR_ICONS.quote,
  bullet: TOOLBAR_ICONS.bullet,
  number: TOOLBAR_ICONS.number,
  check: TOOLBAR_ICONS.check,
  "code-block": TOOLBAR_ICONS["code-block"],
  table: TOOLBAR_ICONS.table,
  rule: TOOLBAR_ICONS.rule,
  upload: TOOLBAR_ICONS.upload,
  embed: EMBED_ICONS.embed,
};

export interface InsertMenuOptions {
  features: ReadonlySet<Feature>;
  extensions: readonly KotobaExtension[];
  /** The node types of the editor. */
  types: ReadonlySet<string>;
  /** Whether the editor can upload files, and open its embed picker. */
  uploads: boolean;
  embeds: boolean;
  openUpload(): void;
  openEmbed(): void;
  announce(message: string): void;
}

export interface InsertMenu {
  /** The items of the extensions: their blocks of text, then their insert items. */
  items: PromptItem[];
  /** Whether the editor can run an item. */
  allows(item: PromptItem): boolean;
  /** The icon of an item, or `null`. */
  icon(item: PromptItem): Element | null;
  /** Runs an item at the caret, in an update; `withText` is the prompt's. Returns what the live region says. */
  $run(item: PromptItem, withText: "below" | "turn_into"): string | null;
}

export function createInsertMenu(editor: LexicalEditor, options: InsertMenuOptions): InsertMenu {
  const specs = options.extensions.flatMap((extension) => extension.blocks ?? []);
  const targets = new Map<string, Target>(turnIntoTargets(options.features, specs).map((target) => [target.id, target]));

  const controls = new Map<string, { control: InsertControl; extension: KotobaExtension }>(
    options.extensions.flatMap((extension) =>
      (extension.insert ?? []).map((control) => [`${extension.name}:${control.command}`, { control, extension }] as const),
    ),
  );

  const items: PromptItem[] = [
    ...specs.flatMap((spec): PromptItem[] =>
      spec.label !== undefined && spec.create !== undefined
        ? [{ id: `ext:${spec.type}`, label: spec.label, command: `ext:${spec.type}`, group: "Basic" }]
        : [],
    ),
    ...[...controls].map(([id, { control, extension }]): PromptItem => ({
      id,
      label: control.label,
      command: id,
      group: control.group ?? extension.name,
      keywords: control.keywords === undefined ? undefined : [...control.keywords],
    })),
  ];

  const allows = (item: PromptItem): boolean => {
    if (item.node !== undefined) return typeof item.node.type === "string" && options.types.has(item.node.type);
    const command = item.command;
    if (command === undefined) return item.text !== undefined;
    if (targets.has(command) || controls.has(command)) return true;
    const feature = INSERT_FEATURES[command];
    if (feature === undefined || !options.features.has(feature)) return false;
    if (command === "upload") return options.uploads;
    if (command === "embed") return options.embeds;
    return true;
  };

  const icon = (item: PromptItem): Element | null => {
    const command = item.command ?? "";
    const control = controls.get(command)?.control;
    if (control?.icon !== undefined) {
      try {
        const element = control.icon();
        element.setAttribute("aria-hidden", "true");
        return element;
      } catch (error) {
        console.error(`Kotoba: the icon of the insert item "${command}" failed`, error);
        return null;
      }
    }
    const shape = ICONS[command];
    return shape === undefined ? null : renderIcon(shape);
  };

  // The block of the caret, and whether it is an empty paragraph.
  const $place = (): { block: LexicalNode | null; empty: boolean } => {
    const block = $caretBlock();
    return { block, empty: $isParagraphNode(block) && block.getTextContent().trim() === "" };
  };

  // A block in place of an empty paragraph, else below the block of the caret.
  const $putBlock = (node: LexicalNode): void => {
    const { block, empty } = $place();
    if (block === null) return;
    if (empty) block.replace(node);
    else block.insertAfter(node);
  };

  const $run = (item: PromptItem, withText: "below" | "turn_into"): string | null => {
    if (item.text !== undefined && item.node === undefined && item.command === undefined) {
      const selection = $getSelection();
      if ($isRangeSelection(selection)) selection.insertText(item.text);
      return `Inserted ${item.label}`;
    }

    if (item.node !== undefined) {
      let node: LexicalNode;
      try {
        node = $parseSerializedNode({ version: 1, ...item.node } as unknown as SerializedLexicalNode);
      } catch (error) {
        console.error(`Kotoba: the insert item "${item.id}" could not make its node`, error);
        return `Could not insert ${item.label}`;
      }
      if (node.isInline()) {
        $getSelection()?.insertNodes([node]);
      } else {
        $putBlock(node);
        if ($isElementNode(node)) node.selectEnd();
        else node.selectNext();
      }
      return `Inserted ${item.label}`;
    }

    const command = item.command ?? "";
    const target = targets.get(command);
    if (target !== undefined) {
      const { block, empty } = $place();
      if (block === null) return null;
      if (empty || withText === "turn_into") {
        $turnInto(editor, block, target);
        return `Turned into ${target.label}`;
      }
      const paragraph = $createParagraphNode();
      block.insertAfter(paragraph);
      paragraph.select();
      if (target.id !== "paragraph") $turnInto(editor, paragraph, target);
      return `Inserted ${target.label}`;
    }

    const extension = controls.get(command);
    if (extension !== undefined) {
      try {
        extension.control.run(editor);
      } catch (error) {
        console.error(`Kotoba: the insert item "${command}" failed`, error);
        return `Could not insert ${item.label}`;
      }
      return `Inserted ${item.label}`;
    }

    switch (command) {
      case "table": {
        const table = $createTableNodeWithDimensions(NEW_TABLE_ROWS, NEW_TABLE_COLUMNS, { rows: true, columns: false });
        $putBlock(table);
        // A place to write after the table (see toolbar.ts).
        if (table.getNextSibling() === null) table.insertAfter($createParagraphNode());
        table.getFirstDescendant()?.selectStart();
        return "Table inserted";
      }
      case "rule": {
        const rule = $createHorizontalRuleNode();
        $putBlock(rule);
        const next = rule.getNextSibling();
        if ($isElementNode(next)) next.selectStart();
        else {
          const paragraph = $createParagraphNode();
          rule.insertAfter(paragraph);
          paragraph.select();
        }
        return "Divider inserted";
      }
      case "upload":
        options.openUpload();
        return null;
      case "embed":
        options.openEmbed();
        return null;
      default:
        return null;
    }
  };

  return { items, allows, icon, $run };
}
