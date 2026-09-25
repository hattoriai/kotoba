import { expect, test } from "@playwright/test";

import { expectNodes, openEditor } from "./support";

test("Tab indents a list item and Shift+Tab outdents it", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("- one");
  await page.keyboard.press("Enter");
  await page.keyboard.type("two");
  await page.keyboard.press("Tab");

  await expect(editable.locator("ul ul li")).toHaveText("two");
  await expect(editable).toBeFocused();
  await expectNodes(page, "list", 2);

  await page.keyboard.press("Shift+Tab");
  await expect(editable.locator("ul ul")).toHaveCount(0);
  await expectNodes(page, "list", 1);

  // A list item that is not indented: Shift+Tab leaves the editor.
  await page.keyboard.press("Shift+Tab");
  await expect(editable).not.toBeFocused();
  await expect(page.locator("#post_body_editor [role=toolbar] button[tabindex='0']")).toBeFocused();
});

test("Tab outside a list leaves the editor", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("A paragraph");
  await page.keyboard.press("Tab");

  await expect(page.locator("#submit")).toBeFocused();
  await expect(editable).toHaveText("A paragraph");
});

test("Escape then Tab leaves a list, so the list is no keyboard trap", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("- item");
  await page.keyboard.press("Escape");
  await page.keyboard.press("Tab");

  await expect(editable).not.toBeFocused();
  await expect(editable.locator("ul ul")).toHaveCount(0);
});

test("the list buttons toggle lists", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("item");

  const numbered = page.getByRole("button", { name: "Numbered list" });
  await numbered.click();
  await expect(editable.locator("ol li")).toHaveText("item");
  await expect(numbered).toHaveAttribute("aria-pressed", "true");

  await numbered.click();
  await expect(editable.locator("ol")).toHaveCount(0);

  await page.getByRole("button", { name: "Check list" }).click();
  await expect(editable.locator("ul.kotoba-check li")).toHaveText("item");
});

test("a click on the box checks a check list item", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("[] buy milk");

  const item = editable.locator("ul.kotoba-check li");
  await expect(item).toHaveAttribute("aria-checked", "false");
  await item.click({ position: { x: 6, y: 8 } });
  await expect(item).toHaveAttribute("aria-checked", "true");

  const [listItem] = await expectNodes(page, "listitem", 1);
  expect(listItem?.checked).toBe(true);
});
