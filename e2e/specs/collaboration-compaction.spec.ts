import { expect, test, type Page, type WebSocketRoute } from "@playwright/test";
import { MOD, focusEnd, openEditor, settle } from "./support";

// The quick page's documents close half a second after the last person leaves, and Issho compacts
// them as they close when that drops enough: a new epoch that continues the last, without the
// deleted characters. Each test deletes a few hundred characters first, so that it does.
const editor = (page: Page) => page.locator("#quick_editor .kotoba-editable");
const status = (page: Page) => page.locator("#quick_editor [data-collab-status]");
const quickSocket = /\/issho\/quick-socket/;
const IDLE = 1_500;

interface Epoch { epoch: string; continues?: string }

async function open(page: Page, id: string, name: string): Promise<void> {
  await openEditor(page, `/collab/quick?document=${id}&name=${name}`, "quick_editor");
  await expect(status(page)).toHaveText("Saved");
}

// The epoch of each snapshot the server sends: the replies to "open".
function epochOf(message: string | Buffer): Epoch | null {
  if (typeof message !== "string") return null;
  const [, , , event, payload] = JSON.parse(message) as [string, string, string, string, { response?: Partial<Epoch> & { engine?: string } }];
  const response = payload?.response;
  return event === "phx_reply" && response?.engine && response.epoch ? { epoch: response.epoch, continues: response.continues } : null;
}

function watchEpochs(page: Page): Epoch[] {
  const epochs: Epoch[] = [];
  page.on("websocket", socket => socket.on("framereceived", frame => {
    const epoch = epochOf(frame.payload);
    if (epoch) epochs.push(epoch);
  }));
  return epochs;
}

// The page's Issho socket through Playwright: `drop()` closes it on both sides, as a network that
// goes away; while `blocked`, each reconnect is closed at once; while `deaf`, nothing the server
// sends arrives, and `missed` lists the events it sent.
interface Control { blocked: boolean; deaf: boolean; missed: string[]; epochs: Epoch[]; drop: () => void }
async function route(page: Page): Promise<Control> {
  let current: WebSocketRoute | null = null;
  const control: Control = {
    blocked: false, deaf: false, missed: [], epochs: [],
    drop: () => void current?.close({ code: 4000, reason: "dropped" }),
  };
  await page.routeWebSocket(quickSocket, socket => {
    if (control.blocked) { void socket.close({ code: 4000, reason: "blocked" }); return; }
    current = socket;
    const server = socket.connectToServer();
    socket.onMessage(message => server.send(message));
    server.onMessage(message => {
      const epoch = epochOf(message);
      if (epoch) control.epochs.push(epoch);
      if (control.deaf) control.missed.push(typeof message === "string" ? (JSON.parse(message) as string[])[3] : "binary");
      else socket.send(message);
    });
  });
  return control;
}

// A few hundred characters typed and deleted, then `kept`: enough deleted text to compact.
async function writeOver(page: Page, kept: string): Promise<void> {
  await editor(page).click();
  await page.keyboard.insertText("deleted words ".repeat(50));
  await expect(status(page)).toHaveText("Saved");
  await page.keyboard.press(`${MOD}+A`);
  await page.keyboard.press("Backspace");
  await page.keyboard.type(kept);
  await expect(status(page)).toHaveText("Saved");
}

test("edits made while away, across a compaction, apply once when the tab comes back", async ({ page, browser }) => {
  const id = crypto.randomUUID();
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  const control = await route(page);
  await open(page, id, "Ada");
  await writeOver(page, "Kept");
  const [{ epoch: first }] = control.epochs;

  // "A" reaches the server, which accepts it, but its reply never comes back; then the connection
  // goes, and "B" waits in the tab.
  control.deaf = true;
  await focusEnd(page, editor(page));
  await page.keyboard.type("A");
  await expect.poll(() => control.missed.filter(event => event === "phx_reply").length).toBeGreaterThan(0);
  control.blocked = true;
  control.drop();
  await expect(status(page)).toContainText("Offline");
  control.deaf = false;
  await page.keyboard.type("B");

  // No one has it open: it closes, compacted.
  await page.waitForTimeout(IDLE);
  control.blocked = false;
  await expect(status(page)).toHaveText("Saved", { timeout: 15_000 });
  const last = control.epochs[control.epochs.length - 1];
  expect(last.continues).toBe(first);
  expect(last.epoch).not.toBe(first);
  await expect(editor(page)).toHaveText("KeptAB");

  // Undo history does not cross the epoch: the deletion it would take back is gone.
  await editor(page).focus();
  for (let n = 0; n < 4; n++) await page.keyboard.press(`${MOD}+Z`);
  await settle(page);
  await expect(editor(page)).toHaveText("KeptAB");
  await expect(status(page)).toHaveText("Saved");

  const context = await browser.newContext();
  const other = await context.newPage();
  await open(other, id, "Grace");
  await expect(editor(other)).toHaveText("KeptAB");
  await context.close();
  expect(errors).toEqual([]);
});

test("a document compacts only when no one has it open", async ({ page, browser }) => {
  const id = crypto.randomUUID();
  const epochs = watchEpochs(page);
  await open(page, id, "Ada");
  await writeOver(page, "Kept");
  const [{ epoch: first }] = epochs;

  // Ada stays: another person who comes finds the same epoch.
  await page.waitForTimeout(IDLE);
  const context = await browser.newContext();
  const other = await context.newPage();
  const seen = watchEpochs(other);
  await open(other, id, "Grace");
  expect(seen).toEqual([{ epoch: first }]);
  await context.close();
  await page.close();

  // Everyone gone: the next visit finds a new epoch that continues the last, with the same text.
  await new Promise(resolve => setTimeout(resolve, IDLE));
  const later = await browser.newContext();
  const visit = await later.newPage();
  const after = watchEpochs(visit);
  await open(visit, id, "Ada");
  expect(after).toHaveLength(1);
  expect(after[0].continues).toBe(first);
  expect(after[0].epoch).not.toBe(first);
  await expect(editor(visit)).toHaveText("Kept");
  await later.close();
});

test("an edit away that names characters compacted meanwhile freezes the editor, keeping the draft", async ({ page, browser }) => {
  const id = crypto.randomUUID();
  const errors: string[] = [];
  const context = await browser.newContext();
  const grace = await context.newPage();
  grace.on("pageerror", error => errors.push(error.message));
  page.on("pageerror", error => errors.push(error.message));
  const control = await route(grace);
  await open(page, id, "Ada");
  await writeOver(page, "keep these words");
  await open(grace, id, "Grace");
  await expect(editor(grace)).toHaveText("keep these words");

  // Grace, away, makes "these" bold.
  control.blocked = true;
  control.drop();
  await expect(status(grace)).toContainText("Offline");
  await focusEnd(grace, editor(grace));
  for (let n = 0; n < 6; n++) await grace.keyboard.press("ArrowLeft");
  for (let n = 0; n < 5; n++) await grace.keyboard.press("Shift+ArrowLeft");
  await settle(grace);
  await grace.keyboard.press(`${MOD}+B`);
  await expect(editor(grace).locator("strong")).toHaveText("these");

  // Ada deletes "these " and leaves: the document compacts, and the deleted characters go.
  await focusEnd(page, editor(page));
  for (let n = 0; n < 5; n++) await page.keyboard.press("ArrowLeft");
  for (let n = 0; n < 6; n++) await page.keyboard.press("Shift+ArrowLeft");
  await settle(page);
  await page.keyboard.press("Backspace");
  await expect(editor(page)).toHaveText("keep words");
  await expect(status(page)).toHaveText("Saved");
  await page.close();
  await grace.waitForTimeout(IDLE);

  // Grace comes back: her bold names characters that are gone, so the server refuses it, and her
  // editor stops with her draft to download.
  control.blocked = false;
  await expect(status(grace)).toHaveText("The server could not save your edits. Your local draft is preserved.", { timeout: 15_000 });
  await expect(grace.locator("#quick_editor").getByRole("button", { name: "Download local draft" })).toBeVisible();
  await expect(editor(grace)).toHaveAttribute("contenteditable", "false");

  const later = await browser.newContext();
  const visit = await later.newPage();
  await open(visit, id, "Ada");
  await expect(editor(visit)).toHaveText("keep words");
  await expect(editor(visit).locator("strong")).toHaveCount(0);
  await later.close();
  await context.close();
  expect(errors).toEqual([]);
});
