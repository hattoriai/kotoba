import { expect, test, type Page } from "@playwright/test";
import { focusEnd, openEditor } from "./support";

// Two shared editors of one room, as two blocks of a notebook: one connection, one list of people,
// and a person's cursor that goes from one editor to the other.
const editor = (page: Page, block: string) => page.locator(`#notebook_${block} .kotoba-editable`);
const carets = (page: Page, block: string) => page.locator(`#notebook_${block} .kotoba-collab-caret`);

async function open(page: Page, notebook: string, name: string): Promise<void> {
  await openEditor(page, `/collab/notebook?document=${notebook}&name=${name}`, "notebook_one");
  for (const block of ["one", "two"]) await expect(page.locator(`#notebook_${block} [data-collab-status]`)).toHaveText("Saved");
}

test("a person's cursor goes from one editor of the room to another", async ({ page, browser }) => {
  const notebook = `notebook:${crypto.randomUUID()}`;
  const joins: string[] = [];
  page.on("websocket", socket => socket.on("framesent", frame => {
    if (typeof frame.payload !== "string") return;
    const [, , topic, event] = JSON.parse(frame.payload) as string[];
    if (event === "phx_join" && topic.startsWith("issho:")) joins.push(topic);
  }));
  await open(page, notebook, "Ada");
  expect(joins).toEqual([`issho:${notebook}`]);

  const context = await browser.newContext();
  const other = await context.newPage();
  await open(other, notebook, "Grace");

  await focusEnd(other, editor(other, "one"));
  await other.keyboard.type("first");
  await expect(editor(page, "one")).toHaveText("first");
  await expect(carets(page, "one")).toHaveCount(1);
  await expect(carets(page, "one")).toContainText("Grace");
  await expect(carets(page, "two")).toHaveCount(0);

  await focusEnd(other, editor(other, "two"));
  await expect(carets(page, "two")).toHaveCount(1);
  await expect(carets(page, "one")).toHaveCount(0);
  await other.keyboard.type("second");
  await expect(editor(page, "two")).toHaveText("second");

  // Leaving the editors takes the cursor away.
  await other.locator("h1").click();
  await expect(carets(page, "two")).toHaveCount(0);
  await context.close();
});
