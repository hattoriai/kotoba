import type { LexicalEditor, PointType } from "lexical";
import type { ExtensionAPI } from "./extensions";

export interface CollabCredentials {
  document_id: string;
  /** The Issho room the document is in: the editors of a room share its people and cursors. */
  room?: string;
  /** Whether the editor lists the room's people (true), or the page does with Issho's list. */
  people?: boolean;
  /** Whether the editor takes part in following, the room's (true), or not (false). */
  follow?: boolean;
  /** Undo: this editor's own steps ("editor"), the page's, across its components ("page"), or none (false). */
  undo?: "page" | "editor" | false;
  token: string;
  socket: string;
  max_channels?: number;
  role: "read" | "write";
  user: { id: string; name: string; color: string };
}

/** A point of the editor: a node's key, an offset in it, and its kind. */
export interface EditorPoint {
  key: string;
  offset: number;
  type: "text" | "element";
}

export interface Collaboration {
  readonly: boolean;
  flush(): Promise<{ epoch: string; revision: number }>;
  updateCredentials(credentials: CollabCredentials): void;
  /** The editor node of a shared node id, or `null`. */
  keyOf(id: string): string | null;
  /** The shared id of an editor node, or `null`. */
  idOf(key: string): string | null;
  /** A range of the editor as a shared selection (`Kotoba.Issho.Place`), in a read; `null` when it has none. */
  sharedOf?(range: { anchor: PointType; focus: PointType }): unknown;
  /** The points of the editor of a shared selection, in a read; `null` when its words are gone. */
  rangeOf?(shared: unknown): { anchor: EditorPoint; focus: EditorPoint } | null;
  dispose(): void;
}

export interface CollaborationHost {
  editor: LexicalEditor;
  api: ExtensionAPI;
  element: HTMLElement;
  surface: HTMLElement;
  editable: HTMLElement;
  credentials: CollabCredentials;
  initialReadonly: boolean;
  announce(message: string): void;
  setReadonly(value: boolean): void;
  refreshCredentials(): Promise<CollabCredentials>;
  readDocument(): unknown;
}

type Factory = (host: CollaborationHost) => Promise<Collaboration>;
let factory: Factory | null = null;

/** The optional bundle receives the editor's own Lexical through this boundary. */
export function registerCollaboration(implementation: Factory): void { factory = implementation; }

export function attachCollaboration(host: CollaborationHost): Promise<Collaboration> {
  if (factory === null) throw new Error("Kotoba collaboration needs enableCollaboration(registerCollaboration) in app.js");
  return factory(host);
}

export function readCollabCredentials(json: string | undefined): CollabCredentials | null {
  if (!json) return null;
  const data = JSON.parse(json) as CollabCredentials;
  if (!data || typeof data.document_id !== "string" || typeof data.token !== "string" || typeof data.socket !== "string" || (data.room !== undefined && typeof data.room !== "string") || (data.people !== undefined && typeof data.people !== "boolean") || (data.undo !== undefined && !["page", "editor", false].includes(data.undo)) || !["read", "write"].includes(data.role) || typeof data.user?.id !== "string" || (data.max_channels !== undefined && !(Number.isInteger(data.max_channels) && data.max_channels > 0))) throw new Error("Invalid Kotoba collaboration credentials");
  return data;
}
