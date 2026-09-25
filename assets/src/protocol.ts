// The document on the wire, in the hidden input and in `kotoba:change`.
//
// The document is the serialized Lexical editor state in the Kotoba
// envelope: `{kotoba: 1, lexical: "0.51", root: {...}}`. This is the form
// that `Kotoba.Document.parse/1` and `Kotoba.Content.cast/1` read.

import type { EditorState, SerializedEditorState, SerializedLexicalNode } from "lexical";

/** The version of the messages between the hook and the server. */
export const PROTOCOL_VERSION = 1;

/** The version of the document envelope. */
export const DOCUMENT_VERSION = 1;

/** The Lexical version that writes the documents. */
export const LEXICAL_VERSION = "0.51";

/** Node types that only the editor uses. They never go to the server. */
export const UPLOAD_MARKER_TYPE = "kotoba-upload";
export const UNKNOWN_TYPE = "kotoba-unknown";

export interface JSONNode {
  type: string;
  children?: JSONNode[];
  [key: string]: unknown;
}

export interface DocumentEnvelope {
  kotoba: number;
  lexical: string;
  root: JSONNode;
}

export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNode(value: unknown): value is JSONNode {
  return isObject(value) && typeof value.type === "string";
}

/**
 * Reads a document from the hidden input or a server message: an envelope,
 * a `{root}` editor state, a bare root node, or one of these as a JSON
 * string. Returns the root node, or `null` when the value is blank or is not
 * a document.
 */
export function readRoot(value: unknown): JSONNode | null {
  let data = value;

  if (typeof data === "string") {
    if (data.trim() === "") return null;
    try {
      data = JSON.parse(data);
    } catch {
      return null;
    }
  }

  if (isNode(data) && data.type === "root") return data;
  if (isObject(data) && isNode(data.root) && data.root.type === "root") return data.root;
  return null;
}

/**
 * Makes a root node safe for `editor.parseEditorState`: a node of a type
 * that the editor does not know becomes a `kotoba-unknown` node that keeps
 * the original JSON, so that the editor shows it and writes it back with no
 * change.
 */
export function prepareRoot(root: JSONNode, knownTypes: ReadonlySet<string>): JSONNode {
  return { ...root, children: prepareChildren(root.children, knownTypes, true) };
}

function prepareChildren(
  children: unknown,
  knownTypes: ReadonlySet<string>,
  topLevel: boolean,
): JSONNode[] {
  if (!Array.isArray(children)) return [];

  return children.filter(isNode).map((child) => {
    if (!knownTypes.has(child.type) || child.type === UNKNOWN_TYPE) {
      return { type: UNKNOWN_TYPE, version: 1, raw: child, inline: !topLevel };
    }
    if (Array.isArray(child.children)) {
      return { ...child, children: prepareChildren(child.children, knownTypes, false) };
    }
    return child;
  });
}

/** Writes the editor state as a document envelope. */
export function toEnvelope(editorState: EditorState): DocumentEnvelope {
  const state: SerializedEditorState = editorState.toJSON();
  return {
    kotoba: DOCUMENT_VERSION,
    lexical: LEXICAL_VERSION,
    root: exportNode(state.root) ?? { type: "root", children: [] },
  };
}

// Upload markers are dropped; unknown nodes are written as they were read.
function exportNode(node: SerializedLexicalNode): JSONNode | null {
  if (node.type === UPLOAD_MARKER_TYPE) return null;

  const json = node as unknown as JSONNode;
  if (json.type === UNKNOWN_TYPE) return isNode(json.raw) ? json.raw : null;

  if (Array.isArray(json.children)) {
    const children: JSONNode[] = [];
    for (const child of json.children) {
      const exported = exportNode(child as unknown as SerializedLexicalNode);
      if (exported !== null) children.push(exported);
    }
    return { ...json, children };
  }

  return json;
}
