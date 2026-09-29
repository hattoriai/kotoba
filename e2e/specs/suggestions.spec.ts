import { expect, test, type Page } from "@playwright/test";

import { MOD, nodesOfType, openEditor, readDocument, selectBack, settle } from "./support";

// The editor page has the Assist menu, answered by KotobaDev.Assist: a fake
// model that streams fixed answers, four characters every 40 ms.

const toolbar = (page: Page) => page.getByRole("toolbar", { name: "Formatting" });
const assistButton = (page: Page) => toolbar(page).getByRole("button", { name: "Assist" });
const panel = (page: Page) => page.locator("#post_body_editor .kotoba-suggestion");
const status = (page: Page) => panel(page).locator(".kotoba-suggestion-status");
const live = (page: Page) => page.locator("#post_body_editor .kotoba-live");
const events = (page: Page) => page.locator("#suggestion-events");

async function blocks(page: Page): Promise<string[]> {
  return (await readDocument(page)).root.children?.map((node) => node.type) ?? [];
}

async function text(page: Page): Promise<string> {
  return (await nodesOfType(page, "text")).map((node) => String(node.text)).join("|");
}

async function ask(page: Page, action: string): Promise<void> {
  await assistButton(page).click();
  await page.getByRole("menuitem", { name: action }).click();
}

test("the Assist menu from the keyboard, a streamed rewrite, accepted and undone", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Keep this rough idea");
  await selectBack(page, 10);
  await settle(page);

  // Alt+F10, then End (Redo), Undo, Assist.
  await page.keyboard.press("Alt+F10");
  await page.keyboard.press("End");
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await expect(assistButton(page)).toBeFocused();
  await expect(assistButton(page)).toHaveAttribute("aria-haspopup", "menu");
  await page.keyboard.press("Enter");

  const menu = page.getByRole("menu", { name: "Assist" });
  await expect(menu).toBeVisible();
  await expect(menu.getByRole("menuitem", { name: "Rewrite" })).toBeFocused();
  await page.keyboard.press("Enter");

  // The text streams in the panel, not in the document.
  await expect(status(page)).toHaveText("Writing…");
  await expect(panel(page)).toHaveAttribute("aria-label", "Rewrite");
  await expect(text(page)).resolves.toBe("Keep this rough idea");
  await expect(status(page)).toHaveText("Done", { timeout: 5000 });
  await expect(panel(page).locator(".kotoba-suggestion-content strong")).toHaveText("clearer");
  await expect(live(page)).toContainText("Suggestion ready");

  // Cmd/Ctrl+Enter in the editor accepts it, in place of the selection.
  await expect(editable).toBeFocused();
  await page.keyboard.press(`${MOD}+Enter`);
  await expect(panel(page)).toBeHidden();
  await expect(live(page)).toHaveText("Suggestion inserted");
  await expect.poll(() => text(page)).toBe("Keep this A |clearer| version: rough idea");
  const bold = (await nodesOfType(page, "text")).find((node) => node.text === "clearer");
  expect(bold?.format).toBe(1);
  await expect(events(page)).toHaveText("accept");

  // One undo step takes it out.
  await page.keyboard.press(`${MOD}+Z`);
  await expect.poll(() => text(page)).toBe("Keep this rough idea");
});

test("a suggestion after the paragraph, with blocks, accepted with its button", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("First paragraph");
  await settle(page);

  await ask(page, "Continue writing");
  await expect(status(page)).toHaveText("Done", { timeout: 5000 });
  await expect(panel(page).locator("h2")).toHaveText("What comes next");
  await panel(page).getByRole("button", { name: "Accept" }).click();

  await expect.poll(() => blocks(page)).toEqual(["paragraph", "heading", "list"]);
  await expect(editable.locator("li em")).toHaveText("last");
});

test("Escape rejects a suggestion: the document and the selection stay", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Nothing changes here");
  await selectBack(page, 4);
  await settle(page);

  await ask(page, "Rewrite");
  await expect(status(page)).toHaveText("Done", { timeout: 5000 });
  await editable.focus();
  await page.keyboard.press("Escape");

  await expect(panel(page)).toBeHidden();
  await expect(live(page)).toHaveText("Suggestion discarded");
  await expect(events(page)).toHaveText("reject");
  expect(await text(page)).toBe("Nothing changes here");
  await expect.poll(() => page.evaluate(() => window.getSelection()?.toString())).toBe("here");
});

test("Stop keeps what has come, and it can still be accepted", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Start");
  await settle(page);

  await ask(page, "Continue writing");
  await expect(status(page)).toHaveText("Writing…");
  await expect(panel(page).locator(".kotoba-suggestion-content")).not.toHaveText("");
  await panel(page).getByRole("button", { name: "Stop" }).click();
  await expect(status(page)).toHaveText("Stopped");
  await expect(events(page)).toHaveText("stop");

  const partial = (await panel(page).locator(".kotoba-suggestion-content").textContent()) ?? "";
  expect(partial.length).toBeLessThan("What comes next One more point And a last one".length);
  // No chunk comes after Stop.
  await page.waitForTimeout(300);
  await expect(panel(page).locator(".kotoba-suggestion-content")).toHaveText(partial);

  await panel(page).getByRole("button", { name: "Accept" }).click();
  await expect(panel(page)).toBeHidden();
  expect((await text(page)).startsWith("Start|")).toBe(true);
});

test("a stream that the server cancels closes the suggestion", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Stays as it is");
  await settle(page);

  await ask(page, "Fail");
  await expect(live(page)).toHaveText("The suggestion was cancelled", { timeout: 5000 });
  await expect(panel(page)).toBeHidden();
  expect(await text(page)).toBe("Stays as it is");
});

test("a stream that the server starts by itself goes at the end", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("One");
  await page.keyboard.press("Enter");
  await page.keyboard.type("Two");
  await page.keyboard.press("ArrowUp");
  await settle(page);

  await page.getByRole("button", { name: "Stream a summary" }).click();
  await expect(panel(page)).toHaveAttribute("aria-label", "Summary");
  await expect(status(page)).toHaveText("Done", { timeout: 5000 });
  await panel(page).getByRole("button", { name: "Accept" }).click();

  await expect.poll(() => blocks(page)).toEqual(["paragraph", "paragraph", "heading", "list"]);
});

test("a new document from the server discards the suggestion", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Draft");
  await settle(page);

  await ask(page, "Continue writing");
  await expect(panel(page)).toBeVisible();
  await page.getByRole("button", { name: "Load sample" }).click();

  await expect(panel(page)).toBeHidden();
  // "stop" while it streams, "reject" once it is done.
  await expect(events(page)).toHaveText(/^(stop|reject)$/);
});
