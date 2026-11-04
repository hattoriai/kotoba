import { expect, test, type Page } from "@playwright/test";
import { attachFiles, focusEnd, openEditor, png, settle } from "./support";
import type { State } from "../../assets/src/collab/model";

// A shared editor keeps sharing whatever the document holds, and an upload
// is in the document even when the browser shares nothing.

const EDITOR = "shared_editor";
const editor = (page: Page) => page.locator(`#${EDITOR} .kotoba-editable`);
const status = (page: Page) => page.locator(`#${EDITOR} [data-collab-status]`);
const attachments = (page: Page) => page.locator(`#${EDITOR} .kotoba-attachment-name`);

async function open(page: Page, id: string, name: string): Promise<string[]> {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  page.on("console", message => { if (message.type() === "error" || message.type() === "warning") errors.push(message.text()); });
  await openEditor(page, `/collab?document=${id}&name=${name}`, EDITOR);
  await expect(status(page)).toHaveText("Saved");
  return errors;
}

// The shared document, as this editor has it.
const state = (page: Page): Promise<State> =>
  page.evaluate(id => (document.getElementById(id) as HTMLElement & { kotobaCollab: { doc: { state: State } } }).kotobaCollab.doc.state, EDITOR);

// With someone else in the document, each accepted change renders the
// document again; the code highlighter then splits the code into tokens, and
// a caret at the start of a line must stay there.
test("typing lines in a code block keeps them in order, and its tokens' types are not shared", async ({ page, context }) => {
  const id = crypto.randomUUID();
  const errors = await open(page, id, "Ada");
  const other = await context.newPage();
  await open(other, id, "Grace");

  await editor(page).click();
  await page.keyboard.type("```elixir ");
  const lines = ['schema "pages" do', "  field :title, :string", "  field :body, Kotoba.Content", "end"];
  for (const [index, line] of lines.entries()) {
    if (index > 0) await page.keyboard.press("Shift+Enter");
    await page.keyboard.type(line);
  }

  await expect(page.locator(`#${EDITOR} code`)).toHaveText(lines.join(""));
  await expect(other.locator(`#${EDITOR} code`)).toHaveText(lines.join(""));
  await expect(status(page)).toHaveText("Saved");
  const atoms = Object.values((await state(page)).texts).flat();
  expect(atoms.some(atom => "highlightType" in atom.attrs)).toBe(false);
  expect(errors).toEqual([]);
});

test("the text of a block deleted on its own, as an agent's deletion leaves it, does not stop sharing", async ({ page, context }) => {
  const id = crypto.randomUUID();
  await open(page, id, "Ada");
  await editor(page).click();
  await page.keyboard.type("Keep me");
  await page.keyboard.press("Enter");
  await page.keyboard.type("Delete my block only");
  await expect(status(page)).toHaveText("Saved");

  // The block goes, its text stays alive in it: out of the document.
  await page.evaluate(id => {
    const collab = (document.getElementById(id) as HTMLElement & { kotobaCollab: { doc: { state: State; change(ops: unknown[]): { ok: boolean } } } }).kotobaCollab;
    const doc = collab.doc.state;
    const block = Object.keys(doc.nodes).find(node =>
      !doc.nodes[node].deleted && doc.nodes[node].data.type === "paragraph" &&
      (doc.orders[node] ?? []).some(child => (doc.texts[child] ?? []).map(atom => atom.text).join("").includes("Delete")));
    collab.doc.change([{ op: "node_visibility", id: block, deleted: true, tag: crypto.randomUUID() }]);
  }, EDITOR);
  await expect(editor(page)).toHaveText("Keep me");

  const other = await context.newPage();
  const errors = await open(other, id, "Grace");
  await focusEnd(other, editor(other));
  await other.keyboard.type(", shared");
  await expect(editor(page)).toHaveText("Keep me, shared");
  await expect(status(other)).toHaveText("Saved");
  expect(errors).toEqual([]);
});

test("an upload goes in the shared document from the server, even when the browser shares nothing", async ({ page, context }) => {
  const id = crypto.randomUUID();
  await open(page, id, "Ada");
  await editor(page).click();
  await page.keyboard.type("before");
  await page.keyboard.press("Enter");
  await page.keyboard.type("after");
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("End");
  await expect(status(page)).toHaveText("Saved");

  // This browser shares no edit from now on, as when its editor broke.
  await page.evaluate(id => {
    const collab = (document.getElementById(id) as HTMLElement & { kotobaCollab: { binding: { capture: () => null } } }).kotobaCollab;
    collab.binding.capture = () => null;
  }, EDITOR);
  await attachFiles(page, EDITOR, [png("shot.png", 4, 3)]);

  const other = await context.newPage();
  await open(other, id, "Grace");
  await expect(attachments(other)).toHaveText(["shot.png"]);
  // After the block that held the marker.
  const order = await editor(other).evaluate(element => Array.from(element.children).map(child => child.textContent?.trim().split("\n")[0] ?? ""));
  expect(order[0]).toBe("before");
  expect(order[1]).toContain("shot.png");
  expect(order[2]).toBe("after");
  // The marker is gone in the browser that uploaded it.
  await expect(page.locator(`#${EDITOR} .kotoba-upload-marker`)).toHaveCount(0);

  await other.locator("#collab-save").click();
  await expect(other.locator("#collab-saved .kotoba-attachment")).toHaveCount(1);
});

test("images uploaded together go in a gallery of the shared document, in their order", async ({ page, context }) => {
  const id = crypto.randomUUID();
  await open(page, id, "Ada");
  await editor(page).click();
  await page.keyboard.type("Pictures");
  await settle(page);
  await attachFiles(page, EDITOR, [png("a.png", 2, 2), png("b.png", 3, 2), png("c.png", 2, 3)]);

  const other = await context.newPage();
  await open(other, id, "Grace");
  await expect(other.locator(`#${EDITOR} .kotoba-gallery .kotoba-attachment-name`)).toHaveText(["a.png", "b.png", "c.png"]);
  await expect(page.locator(`#${EDITOR} .kotoba-gallery .kotoba-attachment-name`)).toHaveText(["a.png", "b.png", "c.png"]);
  await expect(page.locator(`#${EDITOR} .kotoba-upload-marker`)).toHaveCount(0);
});
