import { expect, test, type Page } from "@playwright/test";
import { MOD, focusEnd, openEditor, selectBack, settle } from "./support";
import type { State, Operation, Transaction } from "../../assets/src/collab/model";

const editor = (page: Page) => page.locator("#shared_editor .kotoba-editable");
const status = (page: Page) => page.locator("#shared_editor [data-collab-status]");

async function open(page: Page, id: string, name: string, role = "write"): Promise<void> {
  await openEditor(page, `/collab?document=${id}&name=${name}&role=${role}`, "shared_editor");
  await expect(status(page)).toHaveText(role === "read" ? "Live view" : "Saved");
}

test("two authors share edits, presence, undo, redo and accepted form revisions", async ({ page, context }) => {
  const other = await context.newPage();
  const id = crypto.randomUUID();
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  other.on("pageerror", error => errors.push(error.message));
  await open(page, id, "Ada");
  await open(other, id, "Grace");
  await expect(page.getByRole("list", { name: "People in this document" })).toContainText("Grace");
  await editor(page).click();
  await page.keyboard.type("Hello");
  await expect(editor(other)).toHaveText("Hello");
  await expect(status(page)).toHaveText("Saved");
  await focusEnd(other, editor(other));
  await other.keyboard.type(" world");
  await expect(editor(page)).toHaveText("Hello world");
  await editor(page).focus();
  await page.keyboard.press(`${MOD}+Z`);
  await expect(editor(other)).toHaveText(" world");
  await page.keyboard.press(`${MOD}+Shift+Z`);
  await expect(editor(other)).toHaveText("Hello world");
  await focusEnd(page, editor(page));
  await page.keyboard.type("!");
  await page.locator("#collab-save").click();
  await expect(page.locator("#collab-saved-text")).toHaveText("Hello world!");
  await other.close();
  await expect(page.getByRole("list", { name: "People in this document" })).not.toContainText("Grace");
  expect(errors).toEqual([]);
});

test("offline edits survive reload and merge with online edits", async ({ browser }) => {
  const first = await browser.newContext();
  const second = await browser.newContext();
  const a = await first.newPage();
  const b = await second.newPage();
  const id = crypto.randomUUID();
  await open(a, id, "Ada");
  await open(b, id, "Grace");
  await editor(a).click();
  await a.keyboard.type("abc");
  await expect(editor(b)).toHaveText("abc");
  await first.setOffline(true);
  await expect(status(a)).toContainText("Offline");
  await focusEnd(a, editor(a));
  await a.keyboard.type("X");
  await focusEnd(b, editor(b));
  await b.keyboard.type("Y");
  await expect(status(b)).toHaveText("Saved");
  await first.setOffline(false);
  await a.reload();
  await expect(status(a)).toHaveText("Saved");
  await expect(editor(a)).toHaveText("abcXY");
  await expect(editor(b)).toHaveText("abcXY");
  await first.close();
  await second.close();
});

test("paragraph splits, links, formatting and custom nodes replicate", async ({ page, context }) => {
  const other = await context.newPage();
  const id = crypto.randomUUID();
  await open(page, id, "Ada");
  await open(other, id, "Grace");
  await editor(page).click();
  await page.keyboard.type("one two");
  await selectBack(page, 3);
  await settle(page);
  await page.keyboard.press(`${MOD}+B`);
  await expect(editor(other).locator("strong")).toHaveText("two");
  await page.keyboard.press(`${MOD}+K`);
  await page.getByRole("dialog", { name: "Link" }).getByLabel("URL").fill("https://example.com");
  await page.keyboard.press("Enter");
  await expect(editor(other).locator("a")).toHaveText("two");
  await focusEnd(page, editor(page));
  await page.keyboard.press("Enter");
  await page.keyboard.type("next");
  await expect(editor(other).locator("p")).toHaveCount(2);
  await expect(editor(other).locator("p").last()).toHaveText("next");
  await page.locator("#collab-insert").click();
  await expect(editor(other).locator(".dev-tag")).toHaveText("shared");
  await expect(status(page)).toHaveText("Saved");
});

test("viewers cannot edit or enable writing through the UI", async ({ page, context }) => {
  const other = await context.newPage();
  const id = crypto.randomUUID();
  await open(page, id, "Ada");
  await open(other, id, "Reader", "read");
  await expect(editor(other)).toHaveAttribute("contenteditable", "false");
  await editor(page).click();
  await page.keyboard.type("Shared");
  await expect(editor(other)).toHaveText("Shared");
  await expect(other.getByRole("button", { name: "Bold", exact: true })).toHaveAttribute("aria-disabled", "true");
});

test("an offline edit follows its characters when another author splits the paragraph", async ({ browser }) => {
  const offline = await browser.newContext();
  const online = await browser.newContext();
  const a = await offline.newPage();
  const b = await online.newPage();
  const id = crypto.randomUUID();
  await open(a, id, "Ada");
  await open(b, id, "Grace");
  await editor(a).click();
  await a.keyboard.type("abc");
  await expect(status(a)).toHaveText("Saved");
  await expect(editor(b)).toHaveText("abc");
  await offline.setOffline(true);
  await expect(status(a)).toContainText("Offline");
  await focusEnd(a, editor(a));
  await a.keyboard.press("ArrowLeft");
  await settle(a);
  await a.keyboard.type("X");
  await focusEnd(b, editor(b));
  await settle(b);
  await b.keyboard.press("ArrowLeft");
  await b.keyboard.press("ArrowLeft");
  await settle(b);
  await b.keyboard.press("Enter");
  await expect(editor(b).locator("p")).toHaveText(["a", "bc"]);
  await expect(status(b)).toHaveText("Saved");
  await offline.setOffline(false);
  await expect(status(a)).toHaveText("Saved");
  await expect(editor(a).locator("p")).toHaveText(["a", "bXc"]);
  await expect(editor(b).locator("p")).toHaveText(["a", "bXc"]);
  await offline.close();
  await online.close();
});

test("remote edits wait for an active input composition to finish", async ({ page, context, browserName }) => {
  test.skip(browserName !== "chromium", "Uses Chromium's native IME input commands");
  const other = await context.newPage();
  const id = crypto.randomUUID();
  await open(page, id, "Ada");
  await open(other, id, "Grace");
  await editor(page).click();
  await page.keyboard.type("abc");
  await expect(status(page)).toHaveText("Saved");
  await expect(editor(other)).toHaveText("abc");
  const input = await context.newCDPSession(page);
  await input.send("Input.imeSetComposition", { text: "に", selectionStart: 1, selectionEnd: 1 });
  await expect(editor(page)).toHaveText("abcに");
  await focusEnd(other, editor(other));
  await other.keyboard.type("B");
  await expect(status(other)).toHaveText("Saved");
  await expect(editor(page)).toHaveText("abcに");
  await input.send("Input.insertText", { text: "日本" });
  await expect(status(page)).toHaveText("Saved");
  await expect(editor(page)).toHaveText("abc日本B");
  await expect(editor(other)).toHaveText("abc日本B");
});

test("browser and authority replay the same transactions and character moves", async ({ page }) => {
  await open(page, crypto.randomUUID(), "Ada");
  const mismatch = await page.evaluate(async () => {
    const load = new Function("url", "return import(url)") as (url: string) => Promise<Record<string, unknown>>;
    const model = await load("/assets/kotoba-collab.esm.js") as { apply(state: State, ops: Operation[]): State };
    const phoenix = await load("/vendor/phoenix/phoenix.mjs") as unknown as { Socket: new (path: string) => { connect(): void; disconnect(): void; channel(topic: string, params: object): { join(): { receive(status: string, callback: (payload: unknown) => void): unknown }; push(event: string, payload: unknown): { receive(status: string, callback: (payload: unknown) => void): unknown }; leave(): void } } };
    const credentials = JSON.parse(document.getElementById("shared_editor")!.dataset.collab!);
    const socket = new phoenix.Socket(credentials.socket);
    const channel = socket.channel(`kotoba:${credentials.document_id}`, { token: credentials.token, session: crypto.randomUUID(), pending: [] });
    socket.connect();
    let state = await new Promise<State>(resolve => channel.join().receive("ok", payload => resolve((payload as { state: State }).state)));
    const canonical = (value: unknown): string => JSON.stringify(value, (_key, object: unknown) => object && typeof object === "object" && !Array.isArray(object) ? Object.fromEntries(Object.entries(object).sort(([a], [b]) => a.localeCompare(b))) : object);
    const transact = async (ops: Operation[]): Promise<{ expected: State; actual: State } | null> => {
      const transaction: Transaction = { v: 1, schema: 1, epoch: state.epoch, base_revision: state.revision, id: crypto.randomUUID(), ops };
      await new Promise<void>((resolve, reject) => { const push = channel.push("transaction", transaction); push.receive("ok", () => resolve()); push.receive("error", reject); });
      const expected = model.apply(state, ops);
      expected.revision++;
      state = await new Promise<State>(resolve => channel.push("flush", {}).receive("ok", payload => resolve((payload as { state: State }).state)));
      return canonical(expected) === canonical(state) ? null : { expected, actual: state };
    };
    try {
      let result = await transact([
        { op: "insert_node", id: "buffer", parent: "seed:1", after: null, data: { type: "text", version: 1 }, element: false },
        { op: "insert_node", id: "paragraph", parent: "root", after: "seed:1", data: { type: "paragraph", version: 1 }, element: true },
        { op: "insert_node", id: "buffer2", parent: "paragraph", after: null, data: { type: "text", version: 1 }, element: false },
      ]);
      if (result) return result;
      for (let index = 0; index < 60; index++) {
        const atoms = Object.values(state.texts).flat().filter(atom => !atom.moved_to);
        const atom = atoms[index % Math.max(atoms.length, 1)];
        const target = index % 2 ? "buffer" : "buffer2";
        let ops: Operation[];
        if (!atom || index % 4 === 0) {
          ops = [{ op: "insert_text", id: target, after: atom?.id ?? null, attrs: { type: "text", version: 1 }, atoms: [{ id: `char:${index}`, text: index % 2 ? "😀" : "x" }] }];
        } else if (index % 4 === 1) {
          ops = [{ op: "set_text_attrs", id: "buffer", atoms: [atom.id], values: { bold: index % 3 === 0, italic: index % 5 === 0 }, stamp: `format:${index}` }];
        } else if (index % 4 === 2) {
          ops = [{ op: "text_visibility", id: "buffer", atoms: [atom.id], deleted: index % 3 !== 0, tag: "delete:property" }];
        } else {
          const after = state.texts[target].find(value => value.id !== atom.id && !value.moved_to)?.id ?? null;
          ops = [{ op: "move_text", id: target, after, atoms: [atom.id], stamp: `move:${index}` }];
        }
        result = await transact(ops);
        if (result) return result;
      }
      return null;
    } finally { channel.leave(); socket.disconnect(); }
  });
  expect(mismatch).toBeNull();
});
