// The Lexical editor: its nodes, its theme and its plugins.

import { restoreHostPrism } from "./prism";

import { $isCodeNode, CodeHighlightNode, CodeNode } from "@lexical/code-core";
import { registerCodeHighlighting } from "@lexical/code-prism";
import "prismjs/components/prism-bash";
import "prismjs/components/prism-elixir";
import "prismjs/components/prism-json";
import {
  $createHorizontalRuleNode,
  $isHorizontalRuleNode,
  HorizontalRuleNode,
  INSERT_HORIZONTAL_RULE_COMMAND,
  namedSignals,
} from "@lexical/extension";
import { createEmptyHistoryState, registerHistory } from "@lexical/history";
import {
  AutoLinkNode,
  LinkNode,
  autoLinkEmailMatcher,
  autoLinkUrlMatcher,
  registerAutoLink,
  registerLink,
} from "@lexical/link";
import {
  ListItemNode,
  ListNode,
  registerCheckList,
  registerList,
} from "@lexical/list";
import {
  CHECK_LIST,
  CODE,
  HEADING,
  QUOTE,
  ORDERED_LIST,
  UNORDERED_LIST,
  TEXT_FORMAT_TRANSFORMERS,
  TEXT_MATCH_TRANSFORMERS,
  registerMarkdownShortcuts,
  type ElementTransformer,
  type Transformer,
} from "@lexical/markdown";
import { HeadingNode, QuoteNode, registerRichText } from "@lexical/rich-text";
import { $getNearestNodeOfType, $insertNodeToNearestRoot, $unwrapNode } from "@lexical/utils";
import {
  $getSelection,
  $isRangeSelection,
  COMMAND_PRIORITY_EDITOR,
  INDENT_CONTENT_COMMAND,
  KEY_TAB_COMMAND,
  OUTDENT_CONTENT_COMMAND,
  createEditor,
  mergeRegister,
  type EditorThemeClasses,
  type Klass,
  type LexicalEditor,
  type LexicalNode,
} from "lexical";

import { AttachmentNode } from "./nodes/attachment";
import { registerDecorators } from "./nodes/decorator";
import { UnknownNode, UploadMarkerNode } from "./nodes/internal";
import { MentionNode } from "./nodes/mention";
import { isAbsoluteLinkUrl, isAllowedLinkUrl } from "./links";
import { UNKNOWN_TYPE, UPLOAD_MARKER_TYPE } from "./protocol";

// Every import above has run, so the editor's Prism and its grammars are
// loaded: the host page gets its own `Prism` back.
restoreHostPrism();

/** The node classes that every Kotoba editor has. */
export const BUILT_IN_NODES: readonly Klass<LexicalNode>[] = [
  HeadingNode,
  QuoteNode,
  ListNode,
  ListItemNode,
  LinkNode,
  AutoLinkNode,
  CodeNode,
  CodeHighlightNode,
  HorizontalRuleNode,
  AttachmentNode,
  MentionNode,
  UploadMarkerNode,
  UnknownNode,
];

/** The node types that Lexical registers on every editor. */
const CORE_TYPES = ["root", "paragraph", "text", "linebreak", "tab"];

/** The code languages that the editor highlights. */
export const CODE_LANGUAGES = [
  "elixir",
  "javascript",
  "typescript",
  "json",
  "bash",
  "html",
  "css",
  "markdown",
  "plain",
];

export const THEME: EditorThemeClasses = {
  paragraph: "kotoba-paragraph",
  quote: "kotoba-quote",
  heading: {
    h1: "kotoba-h1",
    h2: "kotoba-h2",
    h3: "kotoba-h3",
    h4: "kotoba-h4",
    h5: "kotoba-h5",
    h6: "kotoba-h6",
  },
  list: {
    ul: "kotoba-ul",
    ol: "kotoba-ol",
    checklist: "kotoba-check",
    listitem: "kotoba-li",
    listitemChecked: "kotoba-li-checked",
    listitemUnchecked: "kotoba-li-unchecked",
    nested: { listitem: "kotoba-li-nested" },
  },
  link: "kotoba-link",
  hr: "kotoba-hr",
  hrSelected: "kotoba-selected",
  code: "kotoba-code",
  codeHighlight: {
    atrule: "kotoba-token-keyword",
    attr: "kotoba-token-attr",
    "attr-name": "kotoba-token-attr",
    "attr-value": "kotoba-token-string",
    boolean: "kotoba-token-constant",
    builtin: "kotoba-token-function",
    cdata: "kotoba-token-comment",
    char: "kotoba-token-string",
    class: "kotoba-token-function",
    "class-name": "kotoba-token-function",
    comment: "kotoba-token-comment",
    constant: "kotoba-token-constant",
    deleted: "kotoba-token-deleted",
    doctype: "kotoba-token-comment",
    entity: "kotoba-token-operator",
    function: "kotoba-token-function",
    important: "kotoba-token-keyword",
    inserted: "kotoba-token-inserted",
    keyword: "kotoba-token-keyword",
    module: "kotoba-token-function",
    namespace: "kotoba-token-variable",
    number: "kotoba-token-constant",
    operator: "kotoba-token-operator",
    prolog: "kotoba-token-comment",
    property: "kotoba-token-attr",
    punctuation: "kotoba-token-punctuation",
    regex: "kotoba-token-string",
    selector: "kotoba-token-attr",
    string: "kotoba-token-string",
    symbol: "kotoba-token-constant",
    tag: "kotoba-token-keyword",
    url: "kotoba-token-string",
    variable: "kotoba-token-variable",
  },
  text: {
    bold: "kotoba-bold",
    italic: "kotoba-italic",
    strikethrough: "kotoba-strike",
    underline: "kotoba-underline",
    underlineStrikethrough: "kotoba-underline kotoba-strike",
    code: "kotoba-inline-code",
    highlight: "kotoba-highlight",
    subscript: "kotoba-sub",
    superscript: "kotoba-sup",
  },
};

// Headings h1–h4 only, as the toolbar offers (`#####` stays text).
const HEADING_1_TO_4: ElementTransformer = { ...HEADING, regExp: /^(#{1,4})\s/ };

const HORIZONTAL_RULE: ElementTransformer = {
  dependencies: [HorizontalRuleNode],
  export: (node) => ($isHorizontalRuleNode(node) ? "---" : null),
  regExp: /^(---|\*\*\*|___)\s?$/,
  replace: (parentNode, _children, _match, isImport) => {
    const rule = $createHorizontalRuleNode();
    if (isImport || parentNode.getNextSibling() !== null) {
      parentNode.replace(rule);
    } else {
      parentNode.insertBefore(rule);
    }
    rule.selectNext();
  },
  type: "element",
};

/** The markdown shortcuts: Lexical's built-in transformers, plus check lists and rules. */
export const MARKDOWN_TRANSFORMERS: Transformer[] = [
  HEADING_1_TO_4,
  QUOTE,
  CHECK_LIST,
  UNORDERED_LIST,
  ORDERED_LIST,
  HORIZONTAL_RULE,
  CODE,
  ...TEXT_FORMAT_TRANSFORMERS,
  ...TEXT_MATCH_TRANSFORMERS,
];

export interface EditorOptions {
  namespace: string;
  nodes: readonly Klass<LexicalNode>[];
  editable: boolean;
}

/** Creates an editor with the built-in nodes and the app's nodes. */
export function createKotobaEditor(options: EditorOptions): LexicalEditor {
  const builtInTypes = new Set(BUILT_IN_NODES.map((klass) => klass.getType()));
  const appNodes = options.nodes.filter((klass) => {
    let type: string;
    try {
      type = klass.getType();
    } catch (error) {
      console.error("Kotoba: an app node class has a getType() that fails; it is not registered", error);
      return false;
    }
    if (typeof type !== "string" || type === "") {
      console.error("Kotoba: an app node class has no type; it is not registered");
      return false;
    }
    if (builtInTypes.has(type) || CORE_TYPES.includes(type)) {
      console.error(`Kotoba: the node type "${type}" is built in; the app node is not registered`);
      return false;
    }
    return true;
  });

  return createEditor({
    namespace: options.namespace,
    nodes: [...BUILT_IN_NODES, ...appNodes],
    theme: THEME,
    editable: options.editable,
    onError: (error) => console.error("Kotoba:", error),
  });
}

/**
 * The node types that a document can have. The internal node types (upload
 * markers, unknown nodes) are left out: a document or an `insert_node` that
 * has one is treated as an unknown node.
 */
export function registeredTypes(editor: LexicalEditor): Set<string> {
  const types = new Set(editor._nodes.keys());
  types.delete(UPLOAD_MARKER_TYPE);
  types.delete(UNKNOWN_TYPE);
  return types;
}

export interface PluginOptions {
  /** The allowed link schemes, as `Kotoba.Sanitizer` has them. */
  linkSchemes: readonly string[];
}

/** The deepest list nesting that Tab makes. */
export const MAX_LIST_INDENT = 6;

/**
 * Tab indents a list item and Shift+Tab outdents it, wherever the caret is
 * in the item. Everywhere else Tab is left to the browser, so it moves the
 * focus out of the editor, and so does Shift+Tab in a list item that is not
 * indented. Code blocks handle Tab themselves (it inserts a tab), at a
 * higher priority.
 */
function registerListTab(editor: LexicalEditor): () => void {
  return editor.registerCommand(
    KEY_TAB_COMMAND,
    (event: KeyboardEvent) => {
      const selection = $getSelection();
      if (!$isRangeSelection(selection)) return false;
      const item = $getNearestNodeOfType(selection.anchor.getNode(), ListItemNode);
      if (item === null) return false;

      const indent = item.getIndent();
      if (event.shiftKey && indent === 0) return false;

      event.preventDefault();
      if (event.shiftKey) return editor.dispatchCommand(OUTDENT_CONTENT_COMMAND, undefined);
      if (indent >= MAX_LIST_INDENT) return true;
      return editor.dispatchCommand(INDENT_CONTENT_COMMAND, undefined);
    },
    COMMAND_PRIORITY_EDITOR,
  );
}

/** Registers the rich text plugins. Returns a function that removes them. */
export function registerPlugins(editor: LexicalEditor, options: PluginOptions): () => void {
  const { linkSchemes } = options;
  // A link from a markdown shortcut, pasted HTML or the server that the
  // server would not keep becomes its text.
  const $unwrapUnsafeLink = (node: LinkNode): void => {
    if (!isAllowedLinkUrl(node.getURL(), linkSchemes)) $unwrapNode(node);
  };

  return mergeRegister(
    registerRichText(editor),
    registerHistory(editor, createEmptyHistoryState(), 300),
    registerList(editor),
    registerCheckList(editor),
    registerListTab(editor),
    registerLink(
      editor,
      namedSignals({ validateUrl: (url: string) => isAbsoluteLinkUrl(url, linkSchemes), attributes: undefined }),
    ),
    registerAutoLink(editor, {
      changeHandlers: [],
      excludeParents: [(parent) => $isCodeNode(parent)],
      matchers: [autoLinkUrlMatcher, autoLinkEmailMatcher],
    }),
    editor.registerNodeTransform(LinkNode, $unwrapUnsafeLink),
    editor.registerNodeTransform(AutoLinkNode, $unwrapUnsafeLink),
    registerMarkdownShortcuts(editor, MARKDOWN_TRANSFORMERS),
    registerCodeHighlighting(editor),
    editor.registerCommand(
      INSERT_HORIZONTAL_RULE_COMMAND,
      () => {
        if (!$isRangeSelection($getSelection())) return false;
        $insertNodeToNearestRoot($createHorizontalRuleNode());
        return true;
      },
      COMMAND_PRIORITY_EDITOR,
    ),
    registerDecorators(editor),
  );
}
