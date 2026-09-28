import { expect, test, type Page } from "@playwright/test";

import { MOD, nodesOfType, openEditor, readDocument, selectBack, settle } from "./support";

const HIGHLIGHT = 128;
const toolbar = (page: Page) => page.getByRole("toolbar", { name: "Formatting" });
const highlightButton = (page: Page) => toolbar(page).getByRole("button", { name: "Highlight", exact: true });
const palette = (page: Page) => page.getByRole("dialog", { name: "Color" });

async function runs(page: Page): Promise<[string, number, string][]> {
  return (await nodesOfType(page, "text")).map((node) => [
    String(node.text ?? ""),
    Number(node.format ?? 0),
    String(node.style ?? ""),
  ]);
}

async function pressed(page: Page): Promise<string[]> {
  return palette(page)
    .locator("[aria-pressed=true]")
    .evaluateAll((all) => all.map((button) => button.getAttribute("aria-label") ?? ""));
}

test("the palette from the keyboard colors the kept selection", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("paint this word");
  await selectBack(page, 4);
  await settle(page);

  // Bold, Italic, Underline, Strikethrough, Highlight.
  await page.keyboard.press("Shift+Tab");
  for (let i = 0; i < 4; i += 1) await page.keyboard.press("ArrowRight");
  await expect(highlightButton(page)).toBeFocused();
  await expect(highlightButton(page)).toHaveAttribute("aria-haspopup", "dialog");
  await expect(highlightButton(page)).toHaveAttribute("aria-expanded", "false");
  await page.keyboard.press("Enter");

  await expect(palette(page)).toBeVisible();
  await expect(highlightButton(page)).toHaveAttribute("aria-expanded", "true");
  // No color yet: the focus is on the first one.
  await expect(palette(page).getByRole("button", { name: "Red text" })).toBeFocused();
  for (let i = 0; i < 4; i += 1) await page.keyboard.press("ArrowRight");
  await expect(palette(page).getByRole("button", { name: "Blue text" })).toBeFocused();
  await page.keyboard.press("Enter");

  await expect(palette(page)).toBeHidden();
  await expect(highlightButton(page)).toHaveAttribute("aria-expanded", "false");
  await expect(editable).toBeFocused();
  await expect(page.locator("#post_body_editor .kotoba-live")).toHaveText("Blue text");
  expect(await page.evaluate(() => window.getSelection()?.toString())).toBe("word");

  await highlightButton(page).click();
  await expect(palette(page).getByRole("button", { name: "Blue text" })).toBeFocused();
  expect(await pressed(page)).toEqual(["Blue text"]);
  await palette(page).getByRole("button", { name: "Green highlight" }).click();

  expect(await runs(page)).toEqual([
    ["paint this ", 0, ""],
    ["word", HIGHLIGHT, "color: var(--kotoba-color-blue);background-color: var(--kotoba-highlight-green);"],
  ]);
  const mark = editable.locator("mark");
  await expect(mark).toHaveText("word");
  await expect(mark).toHaveCSS("background-color", "rgba(34, 197, 94, 0.25)");

  // Escape closes the palette, back to its button.
  await highlightButton(page).click();
  expect(await pressed(page)).toEqual(["Blue text", "Green highlight"]);
  await page.keyboard.press("Escape");
  await expect(palette(page)).toBeHidden();
  await expect(highlightButton(page)).toBeFocused();
});

test("a mixed selection has no color pressed, and a color goes on all of it", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("one two");
  await selectBack(page, 3);
  await settle(page);
  await highlightButton(page).click();
  await palette(page).getByRole("button", { name: "Red highlight" }).click();

  await page.keyboard.press(`${MOD}+A`);
  await settle(page);
  await highlightButton(page).click();
  expect(await pressed(page)).toEqual([]);
  await palette(page).getByRole("button", { name: "Purple highlight" }).click();

  expect(await runs(page)).toEqual([["one two", HIGHLIGHT, "background-color: var(--kotoba-highlight-purple);"]]);
});

test("Remove color takes the colors off, and undo and redo bring them back and forth", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("colored");
  await page.keyboard.press(`${MOD}+A`);
  await settle(page);
  await highlightButton(page).click();
  await palette(page).getByRole("button", { name: "Orange text" }).click();
  await highlightButton(page).click();
  await palette(page).getByRole("button", { name: "Yellow highlight" }).click();
  const colored: [string, number, string][] = [["colored", HIGHLIGHT, "color: var(--kotoba-color-orange);"]];
  expect(await runs(page)).toEqual(colored);

  await highlightButton(page).click();
  await palette(page).getByRole("button", { name: "Remove color" }).click();
  await expect(page.locator("#post_body_editor .kotoba-live")).toHaveText("Color removed");
  expect(await runs(page)).toEqual([["colored", 0, ""]]);

  await page.keyboard.press(`${MOD}+Z`);
  await expect.poll(() => runs(page)).toEqual(colored);
  await page.keyboard.press(`${MOD}+Shift+Z`);
  await expect.poll(() => runs(page)).toEqual([["colored", 0, ""]]);
});

test("the colors are submitted, stored and rendered as classes", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Note: important");
  await selectBack(page, 9);
  await settle(page);
  await highlightButton(page).click();
  await palette(page).getByRole("button", { name: "Red text" }).click();
  await highlightButton(page).click();
  await palette(page).getByRole("button", { name: "Blue highlight" }).click();

  const sent = await readDocument(page);
  await page.getByRole("button", { name: "Submit" }).click();

  const stored = page.locator("#stored-content");
  await expect(stored.locator("span.kotoba-color-red > mark.kotoba-highlight-blue")).toHaveText("important");
  await expect(stored.locator("[style]")).toHaveCount(0);
  const json = JSON.parse((await page.locator("#stored-json").textContent()) ?? "{}");
  expect(json.root).toEqual(sent.root);
});

test("a pasted style that is not a color of the palette is dropped", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await settle(page);
  await editable.evaluate((element) => {
    const data = new DataTransfer();
    data.setData(
      "text/html",
      '<p><span style="color: red; font-size: 40px">red</span> <span style="background-color: var(--kotoba-highlight-green)">bg</span></p>',
    );
    data.setData("text/plain", "red bg");
    element.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
  });

  await expect.poll(() => runs(page)).toEqual([["red bg", 0, ""]]);
});
