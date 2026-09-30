import type { State, Transaction } from "./model";

export interface Backup { state: State; pending: Transaction[]; sent?: string[] }

/** Each tab has its own queue; reloads reuse the tab's session identity. */
export class Persistence {
  private database: IDBDatabase | null = null;
  key: string;
  session: string;
  private readonly scope: string;
  private readonly sessionKey: string;
  private unlock: (() => void) | undefined;

  constructor(socket: string, documentId: string, userId: string) {
    const scope = JSON.stringify([location.origin, socket, documentId, userId]);
    const sessionKey = `kotoba:collab:session:${scope}`;
    this.scope = scope;
    this.sessionKey = sessionKey;
    let session: string = crypto.randomUUID();
    try { session = sessionStorage.getItem(sessionKey) ?? session; sessionStorage.setItem(sessionKey, session); } catch { /* Private storage can be disabled. */ }
    this.session = session;
    this.key = `${scope}:${this.session}`;
  }

  async open(): Promise<Backup | null> {
    if (navigator.locks) await this.claimSession();
    this.database = await new Promise<IDBDatabase>((resolve, reject) => {
      const request = indexedDB.open("kotoba-collab-v1", 1);
      request.onupgradeneeded = () => request.result.createObjectStore("documents");
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
      request.onblocked = () => reject(new Error("Local backup database is blocked"));
    });
    return new Promise<Backup | null>((resolve, reject) => {
      const transaction = this.database!.transaction("documents", "readonly");
      const request = transaction.objectStore("documents").get(this.key);
      request.onsuccess = () => resolve((request.result as Backup | undefined) ?? null);
      request.onerror = () => reject(request.error);
    });
  }

  private claimSession(): Promise<void> {
    return new Promise((resolve, reject) => {
      void navigator.locks.request(`kotoba:${this.key}`, { ifAvailable: true }, lock => {
        if (!lock) {
          this.session = crypto.randomUUID();
          this.key = `${this.scope}:${this.session}`;
          try { sessionStorage.setItem(this.sessionKey, this.session); } catch { /* Storage can be disabled. */ }
          return this.claimSession().then(resolve);
        }
        resolve();
        return new Promise<void>(release => { this.unlock = release; });
      }).catch(reject);
    });
  }

  async save(backup: Backup): Promise<void> {
    if (!this.database) throw new Error("Local backup unavailable");
    return new Promise<void>((resolve, reject) => {
      const transaction = this.database!.transaction("documents", "readwrite");
      transaction.objectStore("documents").put(backup, this.key);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
      transaction.onabort = () => reject(transaction.error);
    });
  }

  close(): void { this.database?.close(); this.database = null; this.unlock?.(); }
}
