import { expect, test, type Page } from "@playwright/test";

import { openEditor, readDocument, settle } from "./support";

// The resume page: KotobaDev.Writer writes the answer in a process of the
// app's, four characters every 40 ms, and a page that mounts resumes it.

const EDITOR = "resume_editor";
const panel = (page: Page) => page.locator(`#${EDITOR} .kotoba-suggestion`);
const content = (page: Page) => panel(page).locator(".kotoba-suggestion-content");
const status = (page: Page) => panel(page).locator(".kotoba-suggestion-status");

async function summarize(page: Page, key: string): Promise<void> {
  const editable = await openEditor(page, `/resume?key=${key}`, EDITOR);
  // The caret in the second paragraph: the answer goes after it.
  await editable.getByText("We agreed").click();
  await settle(page);
  await page.getByRole("toolbar", { name: "Formatting" }).getByRole("button", { name: "Assist" }).click();
  await page.getByRole("menuitem", { name: "Summarize" }).click();
  await expect(content(page)).toContainText("Summary");
}

test("an answer goes on while the person is on another page, and resumes where it got to", async ({ page }) => {
  const key = crypto.randomUUID();
  await summarize(page, key);
  const before = ((await content(page).textContent()) ?? "").length;

  await page.locator("#leave").click();
  await expect(page).toHaveURL(/\/blocks/);
  await page.waitForTimeout(1000);

  await openEditor(page, `/resume?key=${key}`, EDITOR);
  await expect(panel(page)).toBeVisible();
  // At once, further on than when the person left.
  await expect.poll(async () => ((await content(page).textContent()) ?? "").length).toBeGreaterThan(before + 40);
  await expect(status(page)).toHaveText("Done", { timeout: 10_000 });

  await panel(page).getByRole("button", { name: "Accept" }).click();
  // After the block it was asked at.
  await expect
    .poll(async () => (await readDocument(page, "resume_body")).root.children?.map((node) => node.type))
    .toEqual(["paragraph", "paragraph", "heading", "paragraph"]);
  const [, second, heading] = (await readDocument(page, "resume_body")).root.children ?? [];
  expect(JSON.stringify(second)).toContain("We agreed");
  expect(JSON.stringify(heading)).toContain("Summary");

  // Accepted: the app stopped the answer, so a new visit has none.
  await openEditor(page, `/resume?key=${key}`, EDITOR);
  await page.waitForTimeout(500);
  await expect(panel(page)).toBeHidden();
});

test("Stop ends the answer: it does not come back", async ({ page }) => {
  const key = crypto.randomUUID();
  await summarize(page, key);
  await panel(page).getByRole("button", { name: "Stop" }).click();
  await expect(status(page)).toHaveText("Stopped");

  await openEditor(page, `/resume?key=${key}`, EDITOR);
  await page.waitForTimeout(500);
  await expect(panel(page)).toBeHidden();
});

/** Ada's shared editor, with "First" and "Second", and Summarize asked in "First". */
async function askInShared(page: Page, id: string): Promise<void> {
  await openEditor(page, `/collab?document=${id}&name=Ada`, "shared_editor");
  await expect(page.locator("#shared_editor [data-collab-status]")).toHaveText("Saved");
  const editable = page.locator("#shared_editor .kotoba-editable");
  await editable.click();
  await page.keyboard.type("First");
  await page.keyboard.press("Enter");
  await page.keyboard.type("Second");
  await expect(page.locator("#shared_editor [data-collab-status]")).toHaveText("Saved");

  await editable.getByText("First").click();
  await settle(page);
  await page.getByRole("toolbar", { name: "Formatting" }).getByRole("button", { name: "Assist" }).click();
  await page.getByRole("menuitem", { name: "Summarize" }).click();
}

// The collaboration page: Summarize writes an Issho stream (Issho.Streams)
// for the person, at the request's block, and the page shows it with
// Kotoba.Issho.suggestions/4.

test("in a shared document, an Issho stream is a suggestion after its block, found by its shared id", async ({ page }) => {
  await askInShared(page, crypto.randomUUID());
  const suggestion = page.locator("#shared_editor .kotoba-suggestion");
  await expect(suggestion).toHaveAttribute("aria-label", "Summary");
  await expect(suggestion.locator(".kotoba-suggestion-content")).toHaveText("Resumed after its block", { timeout: 5000 });
  await expect(suggestion.locator(".kotoba-suggestion-status")).toHaveText("Done");
  await suggestion.getByRole("button", { name: "Accept" }).click();
  const editable = page.locator("#shared_editor .kotoba-editable");
  await expect(editable.locator(":scope > p")).toHaveText(["First", "Resumed after its block", "Second"]);
});

test("an Issho stream goes on while the person is away, and is closed when they accept it", async ({ page }) => {
  const id = crypto.randomUUID();
  await askInShared(page, id);
  const suggestion = page.locator("#shared_editor .kotoba-suggestion");
  await expect(suggestion.locator(".kotoba-suggestion-content")).toContainText("Resumed");

  await page.goto("/blocks");
  await page.waitForTimeout(1200);
  await openEditor(page, `/collab?document=${id}&name=Ada`, "shared_editor");
  await expect(suggestion.locator(".kotoba-suggestion-content")).toHaveText("Resumed after its block", { timeout: 5000 });
  await expect(suggestion.locator(".kotoba-suggestion-status")).toHaveText("Done");
  await suggestion.getByRole("button", { name: "Accept" }).click();
  const editable = page.locator("#shared_editor .kotoba-editable");
  await expect(editable.locator(":scope > p")).toHaveText(["First", "Resumed after its block", "Second"]);

  // Accepted: Issho closed it, so the next visit has no suggestion.
  await openEditor(page, `/collab?document=${id}&name=Ada`, "shared_editor");
  await expect(page.locator("#shared_editor [data-collab-status]")).toHaveText("Saved");
  await page.waitForTimeout(500);
  await expect(suggestion).toBeHidden();
});
