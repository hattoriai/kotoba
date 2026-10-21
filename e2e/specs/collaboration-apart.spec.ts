import { expect, test, type Page } from "@playwright/test";
import { focusEnd, openEditor } from "./support";

// Two shared editors of two rooms on one page: independent of each other. Each room has its own
// connection and its own people, and a person's cursor stays in the editor of its room.
const editor = (page: Page, block: string) => page.locator(`#apart_${block} .kotoba-editable`);
const carets = (page: Page, block: string) => page.locator(`#apart_${block} .kotoba-collab-caret`);
const people = (page: Page, block: string) => page.locator(`#apart_${block}`).getByRole("list", { name: "People in this document" });

test("two editors of two rooms on a page are independent of each other", async ({ page, browser }) => {
  const first = `notes:${crypto.randomUUID()}`;
  const second = `drafts:${crypto.randomUUID()}`;
  const joins: string[] = [];
  page.on("websocket", socket => socket.on("framesent", frame => {
    if (typeof frame.payload !== "string") return;
    const [, , topic, event] = JSON.parse(frame.payload) as string[];
    if (event === "phx_join" && topic.startsWith("issho:")) joins.push(topic);
  }));

  await openEditor(page, `/collab/apart?first=${first}&second=${second}&name=Ada`, "apart_first");
  for (const block of ["first", "second"]) await expect(page.locator(`#apart_${block} [data-collab-status]`)).toHaveText("Saved");
  expect([...joins].sort()).toEqual([`issho:${second}`, `issho:${first}`].sort());

  // Grace is in the first room only: the second room's editor neither lists her nor shows her cursor.
  const context = await browser.newContext();
  const other = await context.newPage();
  await openEditor(other, `/collab/apart?first=${first}&second=drafts:${crypto.randomUUID()}&name=Grace`, "apart_first");
  await focusEnd(other, editor(other, "first"));
  await other.keyboard.type("hello");

  await expect(editor(page, "first")).toHaveText("hello");
  await expect(carets(page, "first")).toContainText("Grace");
  await expect(people(page, "first")).toContainText("Grace");
  await expect(people(page, "second")).not.toContainText("Grace");
  await expect(editor(page, "second")).toHaveText("");

  await focusEnd(other, editor(other, "second"));
  await other.keyboard.type("elsewhere");
  await expect(carets(page, "second")).toHaveCount(0);
  await expect(editor(page, "second")).toHaveText("");
  await context.close();
});
