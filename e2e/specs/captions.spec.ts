import { expect, test, type Page } from "@playwright/test";

import { MOD, attachFiles, expectNodes, focused, openEditor, png, readDocument, settle, type JSONNode } from "./support";

const EDITOR = "post_body_editor";
const editor = (page: Page) => page.locator(`#${EDITOR}`);
const field = (page: Page) => editor(page).locator(".kotoba-caption-field");
const live = (page: Page) => editor(page).locator(".kotoba-live");

async function attachment(page: Page): Promise<JSONNode | undefined> {
  return (await readDocument(page)).root.children!.find((node) => node.type === "attachment");
}

test("an image takes a caption under it: its alt text and figcaption, undone and redone", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await attachFiles(page, EDITOR, [png("timeline.png", 40, 30)]);
  await expectNodes(page, "attachment", 1);

  // Selected, the image shows the field under it; Alt+F10 moves the focus there.
  await editable.locator(".kotoba-attachment img").click();
  await expect(field(page)).toBeVisible();
  const input = field(page).getByRole("textbox", { name: "Caption of timeline.png" });
  await expect(input).toHaveValue("");
  await expect(input).toHaveAttribute("placeholder", "Add a caption");
  await settle(page);
  await page.keyboard.press("Alt+F10");
  await expect(input).toBeFocused();

  // Enter keeps it, and gives the focus back with the image selected.
  await page.keyboard.type("The timeline of the project");
  await page.keyboard.press("Enter");
  await expect.poll(async () => (await attachment(page))?.caption).toBe("The timeline of the project");
  await expect(live(page)).toHaveText("Caption saved");
  expect(await focused(page)).toBe(`div.kotoba-editable`);
  await expect(editable.locator(".kotoba-attachment")).toHaveClass(/kotoba-selected/);
  await expect(editable.locator(".kotoba-attachment-caption-text")).toHaveText("The timeline of the project");
  await expect(editable.locator(".kotoba-attachment img")).toHaveAttribute("alt", "The timeline of the project");
  await expect(input).toHaveValue("The timeline of the project");

  // One change of the document: one undo, one redo.
  await page.keyboard.press(`${MOD}+Z`);
  await expect.poll(async () => (await attachment(page))?.caption).toBeUndefined();
  await expect(input).toHaveValue("");
  await page.keyboard.press(`${MOD}+Shift+Z`);
  await expect.poll(async () => (await attachment(page))?.caption).toBe("The timeline of the project");

  // Saved: the caption is the image's alt and its figcaption.
  await page.getByRole("button", { name: "Submit" }).click();
  const stored = page.locator("#stored-content figure.kotoba-attachment");
  await expect(stored.locator("img")).toHaveAttribute("alt", "The timeline of the project");
  await expect(stored.locator("figcaption")).toHaveText("The timeline of the project");
});

test("Escape leaves the caption as it was; an empty caption is none; a click away keeps it", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await attachFiles(page, EDITOR, [png("shot.png", 40, 30)]);
  await expectNodes(page, "attachment", 1);
  await editable.locator(".kotoba-attachment img").click();

  const input = field(page).getByRole("textbox", { name: "Caption of shot.png" });
  await input.click();
  await page.keyboard.type("Draft");
  await page.keyboard.press("Escape");
  await expect(input).toHaveValue("");
  expect((await attachment(page))?.caption).toBeUndefined();

  // Escape in the editor hides the field until the selection changes.
  await page.keyboard.press("Escape");
  await expect(field(page)).toBeHidden();
  await editable.locator(".kotoba-attachment img").click();
  await expect(field(page)).toBeVisible();

  // Leaving the field keeps what it holds.
  await input.click();
  await page.keyboard.type("  A   shot  ");
  await page.getByRole("heading", { name: "Kotoba" }).click();
  await expect.poll(async () => (await attachment(page))?.caption).toBe("A shot");
  await expect(field(page)).toBeHidden();

  await editable.locator(".kotoba-attachment img").click();
  await input.click();
  await input.fill("");
  await page.keyboard.press("Enter");
  await expect.poll(async () => (await attachment(page))?.caption).toBeUndefined();
  await expect(live(page)).toHaveText("Caption removed");
  await expect(editable.locator(".kotoba-attachment img")).toHaveAttribute("alt", "shot.png");
});

test("a caption reaches the other authors of a shared document", async ({ page, context }) => {
  const shared = (target: Page) => target.locator("#shared_editor .kotoba-editable");
  const status = (target: Page) => target.locator("#shared_editor [data-collab-status]");
  const other = await context.newPage();
  const id = crypto.randomUUID();
  for (const [target, name] of [
    [page, "Ada"],
    [other, "Grace"],
  ] as const) {
    await openEditor(target, `/collab?document=${id}&name=${name}`, "shared_editor");
    await expect(status(target)).toHaveText("Saved");
  }

  await shared(page).click();
  await page.locator("#collab-attach").click();
  await expect(shared(other).locator(".kotoba-attachment")).toHaveCount(1);

  await shared(page).locator(".kotoba-attachment img").click();
  await page.locator("#shared_editor .kotoba-caption-field input").click();
  await page.keyboard.type("Shared caption");
  await page.keyboard.press("Enter");

  await expect(shared(other).locator(".kotoba-attachment-caption-text")).toHaveText("Shared caption");
  await expect(shared(other).locator(".kotoba-attachment img")).toHaveAttribute("alt", "Shared caption");
  await expect(status(page)).toHaveText("Saved");
});
