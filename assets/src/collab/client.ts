import { defaultDraftStore, joinRoom, registerEngine, releaseRoom, type Peer, type Person as IsshoPerson, type Room, type SharedDocument, type State as IsshoState, type StaleDraft } from "issho";
import type { Collaboration, CollaborationHost, CollabCredentials } from "../collaboration";
import { Binding, COLLAB_TAG, redo, type Change, type SharedSelection } from "./binding";
import { kotobaEngine } from "./engine";
import { apply, clone, envelope, equal, type Operation, type State } from "./model";
import { Presence, type Person } from "./presence";

registerEngine(kotobaEngine);

interface FormBarrier { clients: Set<Client>; resubmit: boolean; busy: boolean; handler: (event: SubmitEvent) => void }
const forms = new WeakMap<HTMLFormElement, FormBarrier>();

// The editors of a page share the room of their documents ("notebook:7" for
// "notebook:7/cell-1"), and with it its people and their cursors: a person's
// cursor goes from one editor to another. Each editor holds the room (Issho's
// joinRoom and releaseRoom), as the page's other components do.
// The editors of each room: its grant is renewed through any of them still on the page.
const editors = new Map<string, Set<Client>>();

async function renew(room: string): Promise<string> {
  for (const client of editors.get(room) ?? []) {
    try { return await client.renewGrant(); } catch { /* The next editor of the room may. */ }
  }
  throw new Error("No editor of the room could renew its grant");
}
const roomOf = (credentials: CollabCredentials): string => credentials.room ?? credentials.document_id.split("/")[0];

class Client implements Collaboration {
  private readRole: boolean;
  get readonly(): boolean { return this.readRole || this.failure !== null || this.doc === null; }
  private credentials: CollabCredentials;
  private readonly binding: Binding;
  private room: Room | null = null;
  private doc: SharedDocument | null = null;
  private readonly presence: Presence;
  private readonly bar: HTMLDivElement;
  private readonly status: HTMLOutputElement;
  private readonly recover: HTMLButtonElement;
  private readonly revisionInput: HTMLInputElement;
  private readonly cleanups: (() => void)[] = [];
  // The document as Lexical shows it: the binding's changes are measured against it.
  private view: State | null = null;
  private undoStack: Change[] = [];
  private redoStack: Change[] = [];
  private lastEdit = 0;
  private connected = false;
  private disposed = false;
  private changing = false;
  private behind = false;
  private failure: string | null = null;
  private recoveryDraft: unknown;
  private readonly localBackup: boolean;
  private readonly drafts: ReturnType<typeof defaultDraftStore>["store"];
  // A form waiting for this editor: given up when it goes offline, fails or closes.
  private waiters: { reject: (reason: Error) => void }[] = [];
  private awarenessTimer: ReturnType<typeof setTimeout> | undefined;
  private lastAwareness = "";

  constructor(private readonly host: CollaborationHost) {
    this.credentials = host.credentials;
    this.readRole = host.credentials.role === "read";
    const drafts = defaultDraftStore();
    this.drafts = drafts.store;
    this.localBackup = drafts.durable;
    this.binding = new Binding(host);
    this.bar = document.createElement("div");
    this.bar.className = "kotoba-collab-bar";
    this.status = document.createElement("output");
    this.status.dataset.collabStatus = "";
    this.status.setAttribute("aria-live", "polite");
    this.status.textContent = "Connecting…";
    this.recover = document.createElement("button");
    this.recover.type = "button";
    this.recover.textContent = "Download local draft";
    this.recover.hidden = true;
    this.recover.addEventListener("click", () => this.download());
    this.bar.append(this.status, this.recover);
    host.element.prepend(this.bar);
    this.presence = new Presence(host, this.binding, () => this.room?.session ?? "", this.bar, host.credentials.people !== false);
    this.revisionInput = document.createElement("input");
    this.revisionInput.type = "hidden";
    this.revisionInput.name = `kotoba_collab[${host.element.id}]`;
    host.element.append(this.revisionInput);
  }

  async start(): Promise<void> {
    this.host.setReadonly(true);
    const api = this.host.api.lexical;
    this.cleanups.push(this.host.editor.registerUpdateListener(({ tags, dirtyElements, dirtyLeaves }) => {
      if (tags.has(COLLAB_TAG) || !this.view || this.readonly || (dirtyElements.size === 0 && dirtyLeaves.size === 0)) return;
      const change = this.binding.capture(this.view);
      if (!change) { this.awareness(); return; }
      const isTyping = (op: Operation): boolean => op.op === "insert_text" || op.op === "text_visibility" || (op.op === "insert_node" && op.data.type === "text") || op.op === "set_attrs";
      const typing = change.forward.some(op => op.op === "insert_text") && change.forward.every(isTyping);
      const last = this.undoStack[this.undoStack.length - 1];
      if (typing && last && Date.now() - this.lastEdit < 300 && last.forward.every(isTyping)) {
        (last.forward as Operation[]).push(...change.forward);
        last.inverse.unshift(...change.inverse);
      } else this.undoStack.push(change);
      this.lastEdit = Date.now();
      this.redoStack = [];
      this.enqueue(change.forward, false);
      this.historyState();
    }));
    this.cleanups.push(this.host.editor.registerCommand(api.UNDO_COMMAND, () => this.history(false), api.COMMAND_PRIORITY_CRITICAL));
    this.cleanups.push(this.host.editor.registerCommand(api.REDO_COMMAND, () => this.history(true), api.COMMAND_PRIORITY_CRITICAL));
    this.cleanups.push(this.host.editor.registerCommand(api.SELECTION_CHANGE_COMMAND, () => { this.awareness(); return false; }, api.COMMAND_PRIORITY_LOW));
    // Transactions wait while a person composes text with an input method; the document renders after.
    // The place is the focused editor's: leaving an editor clears it, unless another editor of the room took it.
    const focus = (): void => this.awareness();
    this.host.editable.addEventListener("focusin", focus);
    this.host.editable.addEventListener("focusout", focus);
    this.cleanups.push(() => {
      this.host.editable.removeEventListener("focusin", focus);
      this.host.editable.removeEventListener("focusout", focus);
    });
    const compositionStart = (): void => this.doc?.hold();
    const compositionEnd = (): void => {
      setTimeout(() => {
        if (this.disposed || this.failure) return;
        if (this.behind) this.render();
        this.doc?.release();
        this.awareness();
      }, 0);
    };
    this.host.editable.addEventListener("compositionstart", compositionStart);
    this.host.editable.addEventListener("compositionend", compositionEnd);
    this.cleanups.push(() => {
      this.host.editable.removeEventListener("compositionstart", compositionStart);
      this.host.editable.removeEventListener("compositionend", compositionEnd);
    });
    this.watchForm();
    (this.host.element as HTMLElement & { kotobaCollab?: Collaboration }).kotobaCollab = this;

    const id = this.credentials.document_id;
    const roomName = roomOf(this.credentials);
    editors.set(roomName, (editors.get(roomName) ?? new Set()).add(this));
    this.cleanups.push(() => editors.get(roomName)?.delete(this));
    try {
      this.room = await joinRoom(roomName, {
        socket: this.credentials.socket,
        token: this.credentials.token,
        maxChannels: this.credentials.max_channels ?? 100,
        self: this.credentials.user.id,
        drafts: this.drafts,
        renew: () => renew(roomName),
      });
      if (this.disposed) { this.release(); return; }
      this.readRole ||= this.room.can === "read";
      this.cleanups.push(this.room.onStaleDraft(stale => this.stale(stale)));
      this.cleanups.push(this.room.onStatus((status, reason) => this.roomStatus(status, reason)));
      this.cleanups.push(this.room.presence.on(() => this.people()));
      this.cleanups.push(this.room.awareness.on(() => this.people()));
      this.doc = await this.room.open(id, { batch: { delay: 80, maxOps: 900 } });
      if (this.disposed) return;
      this.cleanups.push(this.doc.on(event => {
        if (event.type === "change" && !(this.changing && event.origin === "local")) this.render();
        else if (event.type === "refused") this.refused(event.reason);
        if (event.type === "change") this.updateStatus();
      }));
    } catch {
      this.fail("Access to this shared document is unavailable. Your local draft is preserved.");
      return;
    }
    if (this.readonly && this.doc.pending.length > 0) { this.fail("Write access changed. Your local draft is preserved."); return; }
    this.connected = this.room.status === "live";
    this.render(false);
    this.host.setReadonly(this.readonly || this.host.initialReadonly);
    this.people();
    this.updateStatus();
    this.awareness();
  }

  private roomStatus(status: string, reason?: string): void {
    if (this.disposed || this.failure) return;
    if (status === "live") {
      this.connected = true;
      this.lastAwareness = "";
      this.awareness();
    } else if (status === "offline") this.offline();
    else if (status === "ended" && reason !== "left") this.fail("Access to this shared document is unavailable. Your local draft is preserved.");
    this.updateStatus();
  }

  private enqueue(operations: Operation[], render = true): void {
    if (!this.doc || !this.view || operations.length === 0) return;
    operations = operations.map(op => {
      if (op.op !== "insert_text") return op;
      const attrs = op.atoms[0]?.attrs ?? {};
      return { ...op, attrs, atoms: op.atoms.map(atom => ({ id: atom.id, text: atom.text, ...(equal(attrs, atom.attrs) ? {} : { attrs: atom.attrs }) })) };
    });
    this.changing = true;
    const made = this.doc.change(clone(operations) as never);
    this.changing = false;
    if (!made.ok) { this.fail("Your local edits need review. Your local draft is preserved."); return; }
    this.view = apply(this.view, operations);
    if (render) this.binding.render(this.view);
    this.revisionInput.value = "";
    this.updateStatus();
    this.awareness();
  }

  // The document as it is now, into Lexical; while someone composes text, after they finish.
  private render(preserve = true): void {
    if (!this.doc || this.failure) return;
    if (this.host.editor.isComposing()) { this.behind = true; return; }
    this.behind = false;
    const state = this.doc.state as unknown as State;
    try { this.binding.render(state, preserve); } catch { this.fail("A concurrent change needs review. Your local draft is preserved."); return; }
    this.view = state;
    this.presence.draw();
  }

  private refused(reason: string): void {
    console.error("Kotoba collaboration rejected transaction:", reason);
    this.fail(reason === "epoch_mismatch" ? "The shared document changed. Your local draft is preserved." : "The server could not save your edits. Your local draft is preserved.");
  }

  // A draft from before a reload that the document can no longer take.
  private stale(stale: StaleDraft): void {
    if (stale.document !== this.credentials.document_id || !this.view) return;
    let state = clone(this.view);
    for (const transaction of stale.draft.pending) {
      try { state = apply(state, transaction.ops as unknown as Operation[]); } catch { /* It no longer applies. */ }
    }
    this.fail("The shared document changed. Your local draft is preserved.");
    this.recoveryDraft = envelope(state);
  }

  private history(isRedo: boolean): boolean {
    if (this.readonly || this.failure) return true;
    const source = isRedo ? this.redoStack : this.undoStack;
    const target = isRedo ? this.undoStack : this.redoStack;
    const change = source.pop();
    if (!change) return true;
    // An explicit history command returns focus from its toolbar before rendering.
    this.host.editable.focus({ preventScroll: true });
    this.enqueue(isRedo ? redo(change) : change.inverse);
    target.push(change);
    this.lastEdit = 0;
    this.historyState();
    return true;
  }

  private historyState(): void {
    const api = this.host.api.lexical;
    this.host.editor.dispatchCommand(api.CAN_UNDO_COMMAND, this.undoStack.length > 0);
    this.host.editor.dispatchCommand(api.CAN_REDO_COMMAND, this.redoStack.length > 0);
  }

  // The revision with every change of this editor, once the server has accepted them all.
  async flush(): Promise<{ epoch: string; revision: number }> {
    const doc = this.doc;
    if (!this.connected || this.failure || !doc) throw new Error(this.failure ?? "Reconnect before saving this form");
    doc.flush();
    const waiter = { reject: (_reason: Error): void => {} };
    const given = new Promise<never>((_resolve, reject) => { waiter.reject = reject; });
    this.waiters.push(waiter);
    try { await Promise.race([doc.settled(), given]); } finally { this.waiters = this.waiters.filter(other => other !== waiter); }
    const revision = { epoch: doc.epoch, revision: doc.revision };
    this.revisionInput.value = JSON.stringify(revision);
    return revision;
  }

  private watchForm(): void {
    const form = this.host.element.closest("form");
    if (!form) return;
    let barrier = forms.get(form);
    if (!barrier) {
      barrier = { clients: new Set(), resubmit: false, busy: false, handler: () => {} };
      const shared = barrier;
      shared.handler = (event): void => {
        if (shared.resubmit) { shared.resubmit = false; return; }
        event.preventDefault();
        event.stopImmediatePropagation();
        if (shared.busy) return;
        shared.busy = true;
        const editing = [...shared.clients].map(client => ({ client, editable: client.host.editor.isEditable() }));
        editing.forEach(({ client }) => client.host.editor.setEditable(false));
        void Promise.all(editing.map(({ client }) => client.flush())).then(() => {
          shared.resubmit = true;
          form.requestSubmit((event.submitter as HTMLButtonElement | HTMLInputElement | null) ?? undefined);
        }).catch(error => this.host.announce(error instanceof Error ? error.message : "The form could not be saved")).finally(() => {
          shared.busy = false;
          editing.forEach(({ client, editable }) => { if (!client.disposed && !client.failure) client.host.editor.setEditable(editable && !client.readonly); });
        });
      };
      forms.set(form, shared);
      form.addEventListener("submit", shared.handler, true);
    }
    barrier.clients.add(this);
    const shared = barrier;
    this.cleanups.push(() => {
      shared.clients.delete(this);
      if (shared.clients.size === 0) { form.removeEventListener("submit", shared.handler, true); forms.delete(form); }
    });
  }

  private awareness(): void {
    clearTimeout(this.awarenessTimer);
    this.awarenessTimer = setTimeout(() => {
      if (!this.connected || this.failure || this.disposed || !this.room) return;
      const id = this.credentials.document_id;
      const focused = this.host.editable.contains(document.activeElement);
      const selection = this.readonly || !focused ? null : this.binding.selection();
      const signature = JSON.stringify(selection);
      if (signature === this.lastAwareness) return;
      this.lastAwareness = signature;
      const current = this.room.awareness.state?.place as { doc?: string } | null | undefined;
      if (selection) this.room.aware({ place: { doc: id, at: selection as never } });
      else if (!current || current.doc === id) this.room.aware({ place: null });
    }, 40);
  }

  // The people of the room, and the selections of the others in this document.
  private people(): void {
    if (!this.room) return;
    const byKey = new Map<string, IsshoPerson>(this.room.presence.everyone.map(person => [person.key, person]));
    const user = (key: string): Person["user"] => {
      const person = byKey.get(key);
      return { id: key, name: person?.name ?? "Anonymous", color: person?.color ?? "" };
    };
    const role = (key: string): Person["role"] => byKey.get(key)?.can ?? "write";
    const selections = this.room.awareness.peers.flatMap((peer: Peer): Person[] => {
      const place = (peer.state as IsshoState).place as { doc?: string; at?: SharedSelection } | null | undefined;
      if (!place || place.doc !== this.credentials.document_id || !place.at) return [];
      return [{ session: peer.session, role: role(peer.key), user: user(peer.key), selection: place.at }];
    });
    const everyone = [...byKey.keys()].map(key => ({ session: `person:${key}`, role: role(key), user: user(key), selection: null }));
    this.presence.receive([...selections, ...everyone]);
  }

  private offline(): void {
    this.connected = false;
    this.presence.offline();
    this.waiters.splice(0).forEach(waiter => waiter.reject(new Error("Reconnect before saving this form")));
    this.updateStatus();
  }

  private fail(message: string): void {
    if (this.failure) return;
    this.recoveryDraft = this.host.readDocument();
    this.failure = message;
    this.host.setReadonly(true);
    this.recover.hidden = this.view === null;
    this.waiters.splice(0).forEach(waiter => waiter.reject(new Error(message)));
    this.updateStatus();
    this.host.announce(message);
  }

  private updateStatus(): void {
    const pending = (this.doc?.pending.length ?? 0) > 0;
    this.status.textContent = this.failure ?? (!this.connected ? (this.localBackup ? "Offline — edits are kept on this device" : "Offline — edits are kept in this tab") : pending ? "Saving…" : this.readonly ? "Live view" : "Saved");
    this.host.element.dataset.collabState = this.failure ? "error" : !this.connected ? "offline" : pending ? "saving" : "saved";
  }

  private download(): void {
    if (!this.view) return;
    const url = URL.createObjectURL(new Blob([JSON.stringify(this.recoveryDraft ?? envelope(this.view), null, 2)], { type: "application/json" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = "kotoba-local-draft.json";
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1_000);
  }

  updateCredentials(credentials: CollabCredentials): void {
    if (credentials.document_id !== this.credentials.document_id || credentials.user.id !== this.credentials.user.id || credentials.socket !== this.credentials.socket) throw new Error("Collaboration identity cannot change while mounted");
    this.credentials = credentials;
  }

  /** A new token for the room, from the LiveView that granted it. */
  async renewGrant(): Promise<string> {
    if (this.disposed) throw new Error("The editor closed");
    this.updateCredentials(await this.host.refreshCredentials());
    return this.credentials.token;
  }

  // The page leaves the room when no editor or other component holds it.
  private release(): void {
    void releaseRoom(roomOf(this.credentials));
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    clearTimeout(this.awarenessTimer);
    this.waiters.splice(0).forEach(waiter => waiter.reject(new Error("The editor closed")));
    this.cleanups.reverse().forEach(cleanup => cleanup());
    if (this.room) {
      const place = this.room.awareness.state?.place as { doc?: string } | null | undefined;
      if (place?.doc === this.credentials.document_id) this.room.aware({ place: null });
      void this.room.flushDrafts().finally(() => this.release());
    }
    this.presence.dispose();
    this.bar.remove();
    this.revisionInput.remove();
    delete (this.host.element as HTMLElement & { kotobaCollab?: Collaboration }).kotobaCollab;
  }
}

export async function createCollaboration(host: CollaborationHost): Promise<Collaboration> {
  const client = new Client(host);
  await client.start();
  return client;
}
