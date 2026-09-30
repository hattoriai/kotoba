import type { LexicalEditor } from "lexical";
import type { ExtensionAPI } from "./extensions";

export interface CollabCredentials {
  document_id: string;
  token: string;
  socket: string;
  role: "read" | "write";
  user: { id: string; name: string; color: string };
}

export interface Collaboration {
  readonly: boolean;
  flush(): Promise<{ epoch: string; revision: number }>;
  updateCredentials(credentials: CollabCredentials): void;
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
  if (!data || typeof data.document_id !== "string" || typeof data.token !== "string" || typeof data.socket !== "string" || !["read", "write"].includes(data.role) || typeof data.user?.id !== "string") throw new Error("Invalid Kotoba collaboration credentials");
  return data;
}
