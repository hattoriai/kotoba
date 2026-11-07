// Extensions: what an editor is made of.
//
// An extension is a named set of node classes, Markdown shortcuts, toolbar
// controls and a `register` function (commands, transforms, listeners) that
// returns its cleanup. The built-in features of the editor (bold, tables,
// code blocks...) are extensions (see features.ts), and an app adds its own
// from JavaScript modules named in `data-extensions`:
//
//     // assets/js/kotoba/extensions/callout.js
//     export default ({ lexical, utils }) => ({
//       name: "callout",
//       nodes: [CalloutNode],
//       markdown: [CALLOUT_SHORTCUT],
//       toolbar: [{ command: "insert", label: "Callout", run: (editor) => ... }],
//       blocks: [{ type: "callout", label: "Callout", create: () => new CalloutNode() }],
//       insert: [{ command: "note", label: "Note", run: (editor) => ... }],
//       register(editor, context) { return editor.registerCommand(...) },
//     })
//
// The default export is called with the editor's copies of `lexical` and of
// the Lexical packages the editor is made with (see `ExtensionAPI`), once
// for each editor, so that two editors do not share the state of an
// extension. It returns one extension or a list of them. (A Markdown
// shortcut is a plain object: it needs only the types of
// `@lexical/markdown`.)
//
// An extension can also change what the editor has already:
//
//   * `link`: suggestions in the link form, or a link form of its own;
//   * a built-in node: its own state on it (Lexical's NodeState,
//     `lexical.createState`), kept in the JSON under `"$"`, and its DOM
//     (a mutation listener of the node class, `api.nodes`), with the server
//     half in a `Kotoba.Node.Override`;
//   * text marks: an inline element node over the text (`api.inline`).
//
// Order: the built-in features first, then the app's extensions in the order
// of `data-extensions`. Every `register` runs before the document loads, and
// the cleanups run in the reverse order when the editor is destroyed (a
// LiveView remount destroys it and mounts a new one).
//
// Failures do not stop the editor: a module that does not load, an
// extension that is not valid, a name that is taken, a node type that is
// taken and a `register` that throws are logged, and the rest of the
// editor mounts.

import * as code from "@lexical/code-core";
import * as link from "@lexical/link";
import * as list from "@lexical/list";
import * as mark from "@lexical/mark";
import { registerMarkdownShortcuts, type Transformer } from "@lexical/markdown";
import * as richText from "@lexical/rich-text";
import * as selection from "@lexical/selection";
import * as table from "@lexical/table";
import * as utils from "@lexical/utils";
import * as lexical from "lexical";
import type { ElementNode, Klass, LexicalEditor, LexicalNode } from "lexical";

import * as inline from "./inline";
import { AttachmentNode } from "./nodes/attachment";
import { isNodeClass } from "./nodes/custom";
import { EmbedNode } from "./nodes/embed";
import { FootnoteDefinitionNode, FootnoteReferenceNode } from "./nodes/footnote";
import { GalleryNode } from "./nodes/gallery";
import { ImageNode } from "./nodes/image";
import { MentionNode } from "./nodes/mention";

/** A button of the toolbar, from an extension. */
export interface ToolbarControl {
  /** The command, unique in the extension: the toolbar names it `<extension>:<command>`. */
  command: string;
  /** The accessible name and the title of the button. */
  label: string;
  /** The toolbar group of the button; the default is the extension's name. */
  group?: string;
  /** The icon: an element that the toolbar puts in the button. Without one, the button shows the label. */
  icon?: () => Element;
  /** What the live region says when the command has run. */
  done?: string;
  /** Runs the command, in an update of the editor with the selection of the page. */
  run(editor: LexicalEditor): void;
  /** `aria-pressed`, read from the editor state (a `$` function). Without it, the button is not a toggle. */
  isActive?(): boolean;
  /** Whether the button shows, read from the editor state. */
  isVisible?(): boolean;
  /** Whether the button can act now (`aria-disabled` when not), read from the editor state. */
  isEnabled?(): boolean;
}

/** An item of the insert menu (an `insert: :command` prompt), from an extension. */
export interface InsertControl {
  /** The command, unique in the extension: the menu knows it as `<extension>:<command>`. */
  command: string;
  label: string;
  /** The menu's group (a heading over its items); the default is the extension's name. */
  group?: string;
  /** More words that find it. */
  keywords?: readonly string[];
  /** The icon: an element for the item. */
  icon?: () => Element;
  /** Runs the command, in an update of the editor, with the caret where the trigger was. */
  run(editor: LexicalEditor): void;
}

/**
 * A block of an extension's node, for the block handles (the `blocks`
 * feature, see blocks.ts). Every top-level block has a handle; this says
 * how a block of the node's type takes part in the block menu.
 */
export interface BlockSpec {
  /** The node type. */
  type: string;
  /**
   * The words of the menu's Turn into item. With `create`, the menu turns a
   * block into this one, and turns a block of this type into the others.
   */
  label?: string;
  /** Makes an empty block of this type: the text of the block moves into it. */
  create?(): ElementNode;
  /** `false`: a block of this type has no handle (the node handles itself). */
  handle?: boolean;
}

/** What `register` gets besides the editor. */
export interface ExtensionContext {
  /** The editor's id: every event from the editor has it. */
  id: string;
  /** The hook element. */
  element: HTMLElement;
  /** Says a message in the editor's live region. */
  announce(message: string): void;
  /** Pushes an event to the LiveView (or the `phx-target` component). The payload gets the editor's `id`. */
  push(event: string, payload: Record<string, unknown>): void;
  /**
   * Asks the app for a suggestion for the selection (`kotoba:assist` with
   * `action`, the selected text and `detail`), as the Assist menu does.
   * Returns the suggestion's ref, or `null` when the editor has no `assist`.
   */
  assist(action: string, detail?: Record<string, unknown>): string | null;
  /**
   * Pushes an event to the LiveView, as `push`, and resolves with its
   * reply (`{:reply, map, socket}`). It rejects when the editor is
   * destroyed first or the LiveView does not reply in 10 seconds.
   */
  request(event: string, payload: Record<string, unknown>): Promise<unknown>;
}

/** A suggestion of the link form: a link to something of the app. */
export interface LinkSuggestion {
  /** The URL that the link gets. */
  url: string;
  /** What the list shows, and its accessible name. */
  label: string;
  /** A second line: a path, a kind, a date. */
  detail?: string;
  /** The icon: an element for the item. */
  icon?: () => Element;
}

/** What the link form is asked for: the Link button, Cmd/Ctrl+K or the link card's Edit. */
export interface LinkRequest {
  /** The URL of the link at the selection, or `null`. */
  url: string | null;
  /** The selected text. */
  text: string;
  /**
   * Puts the link on the selection of the request (or removes it, with
   * `null`), and gives the focus back to the editor. A URL that the
   * editor's link schemes refuse is not applied: it returns `false`.
   */
  apply(url: string | null): boolean;
}

/** What an extension does with the link form. */
export interface LinkExtension {
  /**
   * Suggestions for the text typed in the form (not for a URL). The form
   * lists the suggestions of every extension, in order, under the input.
   */
  suggest?(query: string, context: ExtensionContext): readonly LinkSuggestion[] | Promise<readonly LinkSuggestion[]>;
  /**
   * A form of its own. It returns `true` when it opened it; then Kotoba's
   * form does not open. The first extension that returns `true` has it.
   */
  open?(request: LinkRequest, context: ExtensionContext): boolean;
}

export interface KotobaExtension {
  /** The name: lower case letters, digits and `-`, unique in the editor. */
  name: string;
  nodes?: readonly Klass<LexicalNode>[];
  /** Markdown shortcuts (transformers of `@lexical/markdown`). */
  markdown?: readonly Transformer[];
  toolbar?: readonly ToolbarControl[];
  /** What the block handles do with the extension's nodes (the `blocks` feature). */
  blocks?: readonly BlockSpec[];
  /** Items of the insert menu. A block with a label and `create` is one already. */
  insert?: readonly InsertControl[];
  /** Suggestions in the link form, or a link form of its own. */
  link?: LinkExtension;
  /** Registers the extension's behaviour. Returns its cleanup. */
  register?(editor: LexicalEditor, context: ExtensionContext): (() => void) | void;
}

/** A toolbar control, with the command that the toolbar knows it by. */
export interface ResolvedControl extends ToolbarControl {
  /** `<extension>:<command>`. */
  id: string;
  group: string;
}

/** Kotoba's own node classes, for a mutation listener, a transform or `instanceof`. */
export const KOTOBA_NODES = {
  AttachmentNode,
  GalleryNode,
  ImageNode,
  MentionNode,
  EmbedNode,
  FootnoteReferenceNode,
  FootnoteDefinitionNode,
} as const;

/**
 * What the default export of an extension module gets: the editor's copies
 * of Lexical and its packages (a class must extend these, not a copy of its
 * own), Kotoba's own node classes, and the inline element functions.
 */
export interface ExtensionAPI {
  lexical: typeof lexical;
  utils: typeof utils;
  selection: typeof selection;
  /** `@lexical/link`: LinkNode, AutoLinkNode, $toggleLink... */
  link: typeof link;
  /** `@lexical/list`. */
  list: typeof list;
  /** `@lexical/table`. */
  table: typeof table;
  /** `@lexical/rich-text`: HeadingNode, QuoteNode... */
  richText: typeof richText;
  /** `@lexical/code-core`: CodeNode, CodeHighlightNode... */
  code: typeof code;
  /** `@lexical/mark`: MarkNode, $wrapSelectionInMarkNode... */
  mark: typeof mark;
  /** Kotoba's own node classes. */
  nodes: typeof KOTOBA_NODES;
  /** An inline element over the selected text: `$toggle` and `$isActive` (see inline.ts). */
  inline: typeof inline;
  /** The version of this contract. */
  version: 1;
}

export const EXTENSION_API: ExtensionAPI = {
  lexical,
  utils,
  selection,
  link,
  list,
  table,
  richText,
  code,
  mark,
  nodes: KOTOBA_NODES,
  inline,
  version: 1,
};

const NAME = /^[a-z][a-z0-9-]*$/;

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Checks an extension from an app module. Returns it, or `null` (with a
 * log) when it is not valid. A control that is not valid is dropped alone.
 */
export function checkExtension(value: unknown, source: string): KotobaExtension | null {
  if (!isObject(value) || typeof value.name !== "string" || !NAME.test(value.name)) {
    console.error(`Kotoba: ${source} gives an extension without a valid name (lower case letters, digits and -)`);
    return null;
  }
  const name = value.name;

  if (value.nodes !== undefined && (!Array.isArray(value.nodes) || !value.nodes.every(isNodeClass))) {
    console.error(`Kotoba: the extension "${name}" has nodes that are not node classes of the editor's Lexical`);
    return null;
  }
  if (value.register !== undefined && typeof value.register !== "function") {
    console.error(`Kotoba: the register of the extension "${name}" is not a function`);
    return null;
  }
  if (value.markdown !== undefined && !Array.isArray(value.markdown)) {
    console.error(`Kotoba: the markdown of the extension "${name}" is not a list of transformers`);
    return null;
  }

  const toolbar: ToolbarControl[] = [];
  const commands = new Set<string>();
  for (const control of Array.isArray(value.toolbar) ? value.toolbar : []) {
    if (
      !isObject(control) ||
      typeof control.command !== "string" ||
      !NAME.test(control.command) ||
      typeof control.label !== "string" ||
      control.label.trim() === "" ||
      typeof control.run !== "function"
    ) {
      console.error(`Kotoba: the extension "${name}" has a toolbar control without a valid command, label and run`);
      continue;
    }
    if (commands.has(control.command)) {
      console.error(`Kotoba: the extension "${name}" has the toolbar command "${control.command}" twice`);
      continue;
    }
    commands.add(control.command);
    toolbar.push(control as unknown as ToolbarControl);
  }

  const blocks: BlockSpec[] = [];
  for (const block of Array.isArray(value.blocks) ? value.blocks : []) {
    if (
      !isObject(block) ||
      typeof block.type !== "string" ||
      (block.label !== undefined && (typeof block.label !== "string" || block.label.trim() === "")) ||
      (block.create !== undefined && typeof block.create !== "function") ||
      (block.handle !== undefined && typeof block.handle !== "boolean")
    ) {
      console.error(`Kotoba: the extension "${name}" has a block without a valid type, label, create and handle`);
      continue;
    }
    blocks.push(block as unknown as BlockSpec);
  }

  const insert: InsertControl[] = [];
  const inserts = new Set<string>();
  for (const item of Array.isArray(value.insert) ? value.insert : []) {
    if (
      !isObject(item) ||
      typeof item.command !== "string" ||
      !NAME.test(item.command) ||
      typeof item.label !== "string" ||
      item.label.trim() === "" ||
      typeof item.run !== "function" ||
      inserts.has(item.command)
    ) {
      console.error(`Kotoba: the extension "${name}" has an insert item without a valid command, label and run`);
      continue;
    }
    inserts.add(item.command);
    insert.push(item as unknown as InsertControl);
  }

  let linkSpec: LinkExtension | undefined;
  if (value.link !== undefined) {
    const spec = value.link;
    if (
      !isObject(spec) ||
      (spec.suggest !== undefined && typeof spec.suggest !== "function") ||
      (spec.open !== undefined && typeof spec.open !== "function")
    ) {
      console.error(`Kotoba: the link of the extension "${name}" is not an object with suggest and open functions`);
    } else {
      linkSpec = spec as unknown as LinkExtension;
    }
  }

  return { ...(value as unknown as KotobaExtension), toolbar, blocks, insert, link: linkSpec };
}

/** Loads the app's extension modules. */
export async function loadExtensions(urls: readonly string[]): Promise<KotobaExtension[]> {
  const lists = await Promise.all(urls.map(loadExtensionModule));
  return lists.flat();
}

async function loadExtensionModule(url: string): Promise<KotobaExtension[]> {
  try {
    const module: Record<string, unknown> = await import(/* webpackIgnore: true */ /* @vite-ignore */ url);
    if (typeof module.default !== "function") {
      console.error(`Kotoba: the extension module ${url} has no default export function`);
      return [];
    }
    const made: unknown = (module.default as (api: ExtensionAPI) => unknown)(EXTENSION_API);
    const list = Array.isArray(made) ? made : [made];
    return list.map((value) => checkExtension(value, url)).filter((value) => value !== null);
  } catch (error) {
    console.error(`Kotoba: could not load the extension module ${url}`, error);
    return [];
  }
}

/**
 * The extensions of an editor, in order, and their node classes: an
 * extension whose name is taken, or with a node type that an earlier
 * extension (or `reserved`) has, is left out with a log.
 */
export function composeExtensions(
  extensions: readonly KotobaExtension[],
  reserved: ReadonlySet<string>,
): { extensions: KotobaExtension[]; nodes: Klass<LexicalNode>[] } {
  const names = new Set<string>();
  const types = new Set<string>(reserved);
  const kept: KotobaExtension[] = [];
  const nodes: Klass<LexicalNode>[] = [];

  for (const extension of extensions) {
    if (names.has(extension.name)) {
      console.error(`Kotoba: the extension name "${extension.name}" is taken; the second one is left out`);
      continue;
    }

    let own: string[];
    try {
      own = (extension.nodes ?? []).map((klass) => klass.getType());
    } catch (error) {
      console.error(`Kotoba: a node class of the extension "${extension.name}" has a getType() that fails`, error);
      continue;
    }
    const clash = own.find((type) => types.has(type) || own.indexOf(type) !== own.lastIndexOf(type));
    if (clash !== undefined) {
      console.error(`Kotoba: the node type "${clash}" of the extension "${extension.name}" is taken; the extension is left out`);
      continue;
    }

    names.add(extension.name);
    for (const type of own) types.add(type);
    nodes.push(...(extension.nodes ?? []));
    kept.push(extension);
  }

  return { extensions: kept, nodes };
}

/** The toolbar controls of the extensions, with their `<extension>:<command>` ids. */
export function extensionControls(extensions: readonly KotobaExtension[]): ResolvedControl[] {
  return extensions.flatMap((extension) =>
    (extension.toolbar ?? []).map((control) => ({
      ...control,
      id: `${extension.name}:${control.command}`,
      group: control.group ?? extension.name,
    })),
  );
}

/**
 * Registers the extensions on the editor, in order, and their Markdown
 * shortcuts (the ones whose nodes the editor has). A `register` that
 * throws is logged; the others still register. Returns the cleanup of all
 * of them, which runs in the reverse order.
 */
export function registerExtensions(
  editor: LexicalEditor,
  extensions: readonly KotobaExtension[],
  context: ExtensionContext,
): () => void {
  const cleanups: (() => void)[] = [];

  for (const extension of extensions) {
    if (extension.register === undefined) continue;
    try {
      const cleanup = extension.register(editor, context);
      if (typeof cleanup === "function") cleanups.push(cleanup);
    } catch (error) {
      console.error(`Kotoba: the extension "${extension.name}" could not register`, error);
    }
  }

  const transformers = markdownTransformers(editor, extensions, (extension) =>
    console.error(`Kotoba: a Markdown shortcut of the extension "${extension.name}" needs a node the editor does not have`),
  );
  if (transformers.length > 0) cleanups.push(registerMarkdownShortcuts(editor, transformers));

  return () => {
    for (const cleanup of cleanups.reverse()) {
      try {
        cleanup();
      } catch (error) {
        console.error("Kotoba: an extension cleanup failed", error);
      }
    }
  };
}

/**
 * The Markdown shortcuts of the extensions, in order, whose nodes the
 * editor has. `onMissing` hears of the extensions with one that it has not.
 */
export function markdownTransformers(
  editor: LexicalEditor,
  extensions: readonly KotobaExtension[],
  onMissing: (extension: KotobaExtension) => void = () => {},
): Transformer[] {
  return extensions.flatMap((extension) =>
    (extension.markdown ?? []).filter((transformer) => {
      const dependencies = "dependencies" in transformer ? transformer.dependencies : [];
      if (editor.hasNodes(dependencies as Klass<LexicalNode>[])) return true;
      onMissing(extension);
      return false;
    }),
  );
}
