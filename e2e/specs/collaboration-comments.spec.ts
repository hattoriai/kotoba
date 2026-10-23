import { expect, test, type Page } from "@playwright/test";
import { openEditor } from "./support";

// Issho's comments with a Kotoba editor as the comment box, and the room's
// events of the shared document's changes, on the /collab page.

const editor = (page: Page) => page.locator("#shared_editor .kotoba-editable");
const box = (page: Page) => page.locator("#comments form.issho-composer").first().locator(".kotoba-editable");

async function open(page: Page, id: string, name: string): Promise<void> {
  await openEditor(page, `/collab?document=${id}&name=${name}`, "shared_editor");
  await expect(page.locator("#shared_editor [data-collab-status]")).toHaveText("Saved");
}

test("a comment written in a Kotoba editor mentions whom its @ picked", async ({ page, context }) => {
  const other = await context.newPage();
  const id = crypto.randomUUID();
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await open(page, id, "Ada");
  await open(other, id, "Grace");

  await box(page).click();
  await page.keyboard.type("Ask @gr");
  const options = page.getByRole("listbox", { name: "People" }).getByRole("option");
  await expect(options).toHaveCount(1);
  await expect(options.first()).toContainText("Grace");
  await page.keyboard.press("Enter");
  await expect(box(page).locator(".kotoba-mention")).toHaveText("Grace");
  await page.keyboard.type("about it");
  await page.locator("#comments").getByRole("button", { name: "Comment", exact: true }).click();

  for (const each of [page, other]) {
    const comment = each.locator("#comments .issho-comment-body").first();
    await expect(comment).toHaveText("Ask @Grace about it");
    await expect(comment.locator(".issho-mention")).toHaveText("@Grace");
  }

  // The next comment box is a new, empty editor.
  await expect(box(page)).toHaveText("");

  // An edit starts from the comment as it is, its mention a mention again.
  await page.locator("#comments .issho-comment-body").first().hover();
  await page.getByRole("button", { name: "Edit comment" }).click();
  const edit = page.locator("#comments form[phx-submit='save'] .kotoba-editable");
  await expect(edit.locator(".kotoba-mention")).toHaveText("Grace");
  await edit.click();
  await page.keyboard.press("End");
  await page.keyboard.type(" today");
  await page.locator("#comments").getByRole("button", { name: "Save", exact: true }).click();
  const comment = other.locator("#comments .issho-comment-body").first();
  await expect(comment).toHaveText("Ask @Grace about it today");
  await expect(comment.locator(".issho-mention")).toHaveText("@Grace");
  expect(errors).toEqual([]);
});

test("the @ of a comment offers mentionable, who is not here", async ({ page }) => {
  await open(page, crypto.randomUUID(), "Ada");
  await box(page).click();
  await page.keyboard.type("@li");
  const options = page.getByRole("listbox", { name: "People" }).getByRole("option");
  await expect(options).toHaveCount(1);
  await expect(options.first()).toContainText("Linus");
});

test("the shared document's changes are events of the room", async ({ page }) => {
  await open(page, crypto.randomUUID(), "Ada");
  const events = page.locator("#collab-events");
  await editor(page).click();
  await page.keyboard.type("Hello");
  await expect(events.locator("li").first()).toHaveText("text.changed: paragraph 1");
  await page.keyboard.press("Enter");
  await expect(events).toContainText("text.block_added: paragraph 2");
});
