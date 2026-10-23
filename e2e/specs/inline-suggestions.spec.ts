import { expect, test, type Page } from "@playwright/test";

import { MOD, nodesOfType, openEditor, readDocument, selectBack, settle } from "./support";

// The editor page with `?inline=true`: the Assist menu's suggestions, from
// KotobaDev.Assist (four characters every 40 ms), stream in the text.

const EDITOR = "#post_body_editor";
const assistButton = (page: Page) => page.getByRole("toolbar", { name: "Formatting" }).getByRole("button", { name: "Assist" });
const panel = (page: Page) => page.locator(`${EDITOR} .kotoba-suggestion`);
const status = (page: Page) => panel(page).locator(".kotoba-suggestion-status");
const pending = (page: Page) => page.locator(`${EDITOR} .kotoba-editable .kotoba-pending`);

async function text(page: Page): Promise<string> {
  return (await nodesOfType(page, "text")).map((node) => String(node.text)).join("|");
}

async function ask(page: Page, action: string): Promise<void> {
  await assistButton(page).click();
  await page.getByRole("menuitem", { name: action }).click();
}

async function typed(page: Page, words: string): Promise<void> {
  const editable = await openEditor(page, "/?inline=true");
  await editable.click();
  await page.keyboard.type(words);
  await settle(page);
}

test("a rewrite streams in the text, after the words it replaces, and is one undo step", async ({ page }) => {
  await typed(page, "Keep this rough idea");
  await selectBack(page, 10);
  await settle(page);
  await ask(page, "Rewrite");

  // In the line, after the selection; the document has not changed.
  await expect(pending(page)).toHaveClass(/kotoba-pending-inline/);
  await expect(status(page)).toHaveText("Writing…");
  await expect(panel(page)).toHaveClass(/kotoba-suggestion-floating/);
  await expect(text(page)).resolves.toBe("Keep this rough idea");
  await expect(status(page)).toHaveText("Done", { timeout: 5000 });
  await expect(pending(page).locator("strong")).toHaveText("clearer");
  await expect(pending(page)).toContainText("A clearer version: rough idea");
  await expect(pending(page).locator(".kotoba-suggestion-content")).toHaveAttribute("aria-label", "Suggestion, not accepted");
  // Nothing of it in the saved document.
  expect(JSON.stringify(await readDocument(page))).not.toContain("kotoba-pending");

  await page.locator(`${EDITOR} .kotoba-editable`).focus();
  await page.keyboard.press(`${MOD}+Enter`);
  await expect(pending(page)).toHaveCount(0);
  await expect(panel(page)).toBeHidden();
  await expect.poll(() => text(page)).toBe("Keep this A |clearer| version: rough idea");

  await page.keyboard.press(`${MOD}+z`);
  await expect.poll(() => text(page)).toBe("Keep this rough idea");
  await expect(pending(page)).toHaveCount(0);
});

test("a selection that ends in a word: shown below, and accepted in place of the selection", async ({ page }) => {
  await typed(page, "Keep this rough idea");
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await selectBack(page, 6);
  await settle(page);
  await ask(page, "Rewrite");

  await expect(status(page)).toHaveText("Done", { timeout: 5000 });
  await expect(pending(page)).not.toHaveClass(/kotoba-pending-inline/);
  await expect.poll(() => text(page)).toBe("Keep this rough idea");

  await page.locator(`${EDITOR} .kotoba-editable`).focus();
  await page.keyboard.press(`${MOD}+Enter`);
  await expect(pending(page)).toHaveCount(0);
  await expect.poll(() => text(page)).toBe("Keep this roA |clearer| version: ugh idea");
});

test("a summary streams as a block below, and Escape rejects it", async ({ page }) => {
  await typed(page, "First words of a long text");
  await selectBack(page, 4);
  await settle(page);
  await ask(page, "Summarize");

  await expect(pending(page)).toBeVisible();
  await expect(pending(page)).not.toHaveClass(/kotoba-pending-inline/);
  await expect(status(page)).toHaveText("Done", { timeout: 5000 });
  await expect(pending(page)).toContainText("Summary:");
  // The block is after the paragraph.
  const paragraph = (await page.locator(`${EDITOR} .kotoba-editable > p`).first().boundingBox())!;
  const block = (await pending(page).boundingBox())!;
  expect(block.y).toBeGreaterThan(paragraph.y);

  await page.locator(`${EDITOR} .kotoba-editable`).focus();
  await page.keyboard.press("Escape");
  await expect(pending(page)).toHaveCount(0);
  await expect(panel(page)).toBeHidden();
  expect((await readDocument(page)).root.children?.map((node) => node.type)).toEqual(["paragraph"]);
});

test("the person writes on while it streams, an undo keeps it, and accepting puts it in its place", async ({ page }) => {
  await typed(page, "Hello");
  await page.getByRole("button", { name: "Stream a summary" }).click();
  await expect(pending(page)).toBeVisible();
  await expect(status(page)).toHaveText("Writing…");

  // Typing and undoing elsewhere leave the suggestion where it is.
  await page.locator(`${EDITOR} .kotoba-editable > p`).first().click();
  await page.keyboard.press("End");
  await settle(page);
  await page.keyboard.type("!");
  await expect.poll(() => text(page)).toBe("Hello!");
  await page.keyboard.press(`${MOD}+z`);
  await expect.poll(() => text(page)).toBe("Hello");
  await expect(pending(page)).toHaveCount(1);

  await expect(status(page)).toHaveText("Done", { timeout: 5000 });
  await page.keyboard.press(`${MOD}+Enter`);
  await expect(pending(page)).toHaveCount(0);
  await expect.poll(async () => (await readDocument(page)).root.children?.map((node) => node.type)).toEqual([
    "paragraph",
    "heading",
    "list",
  ]);

  // Undo takes the suggestion out, and no pending node comes back.
  await page.keyboard.press(`${MOD}+z`);
  await expect.poll(async () => (await readDocument(page)).root.children?.map((node) => node.type)).toEqual(["paragraph"]);
  await expect(pending(page)).toHaveCount(0);
});

test("deleting the suggestion rejects it", async ({ page }) => {
  await typed(page, "Hello");
  await page.getByRole("button", { name: "Stream a summary" }).click();
  await expect(status(page)).toHaveText("Done", { timeout: 5000 });

  // Select all and type over everything, the suggestion too.
  await page.locator(`${EDITOR} .kotoba-editable`).focus();
  await page.keyboard.press(`${MOD}+a`);
  await page.keyboard.type("Over");
  await expect(pending(page)).toHaveCount(0);
  await expect(panel(page)).toBeHidden();
  await expect(page.locator("#suggestion-events")).toContainText("reject");
  await expect.poll(() => text(page)).toBe("Over");
});

test("in a shared editor, only the person who asked sees it, until they accept it", async ({ page, context }) => {
  const other = await context.newPage();
  const id = crypto.randomUUID();
  const shared = (on: Page) => on.locator("#shared_editor .kotoba-editable");
  for (const [on, name] of [
    [page, "Ada"],
    [other, "Grace"],
  ] as const) {
    await openEditor(on, `/collab?document=${id}&name=${name}`, "shared_editor");
    await expect(on.locator("#shared_editor [data-collab-status]")).toHaveText("Saved");
  }

  await shared(page).click();
  await page.keyboard.type("Notes");
  await expect(shared(other)).toHaveText("Notes");

  await page.getByRole("button", { name: "Stream a summary in the text" }).click();
  const mine = page.locator("#shared_editor .kotoba-editable .kotoba-pending");
  await expect(mine).toContainText("What comes next", { timeout: 5000 });
  await expect(page.locator("#shared_editor .kotoba-suggestion-status")).toHaveText("Done", { timeout: 5000 });

  // Grace sees none of it, and her edits go on.
  await expect(other.locator("#shared_editor .kotoba-pending")).toHaveCount(0);
  await expect(shared(other)).toHaveText("Notes");
  await shared(other).locator("p").first().click();
  await other.keyboard.press("End");
  await settle(other);
  await other.keyboard.type("!");
  await expect(shared(page).locator("p").first()).toHaveText("Notes!");
  await expect(mine).toBeVisible();

  await shared(page).focus();
  await page.keyboard.press(`${MOD}+Enter`);
  await expect(mine).toHaveCount(0);
  await expect(shared(other).locator("h2")).toHaveText("What comes next");
  await expect(shared(other).locator("li")).toHaveText(["One more point", "And a last one"]);
});
