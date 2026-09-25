import { expect, test, type Page } from "@playwright/test";

import { expectNodes, openEditor } from "./support";

const menu = (page: Page) => page.locator("#post_body_editor .kotoba-menu");
const listbox = (page: Page) => page.getByRole("listbox", { name: "people suggestions" });

test("@ opens the menu under the caret with the server's results", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Hello @");
  const caret = await page.evaluate(() => {
    const rect = window.getSelection()!.getRangeAt(0).getBoundingClientRect();
    return { left: rect.left, bottom: rect.bottom };
  });

  await expect(menu(page)).toBeVisible();
  const box = (await menu(page).boundingBox())!;
  expect(box.y).toBeGreaterThanOrEqual(caret.bottom);
  expect(box.y - caret.bottom).toBeLessThan(10);
  expect(Math.abs(box.x - caret.left)).toBeLessThan(2);

  await page.keyboard.type("ma");
  const options = listbox(page).getByRole("option");
  await expect(options).toHaveCount(1);
  await expect(options.first().locator(".kotoba-menu-label")).toHaveText("Margaret Hamilton");
  await expect(options.first().locator(".kotoba-menu-hint")).toHaveText("Engineer");
});

test("arrows move the active option and Enter inserts a mention", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("@al");

  const options = listbox(page).getByRole("option");
  await expect(options).toHaveCount(1);
  await expect(options.first()).toContainText("Alan Turing");
  await expect(options.first()).toContainText("Mathematician");

  await page.keyboard.press("Backspace");
  await expect(options).toHaveCount(6);
  await expect(editable).toHaveAttribute("aria-activedescendant", "post_body_editor-option-0");
  await expect(options.nth(0)).toHaveAttribute("aria-selected", "true");

  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("ArrowDown");
  await expect(editable).toHaveAttribute("aria-activedescendant", "post_body_editor-option-2");
  await expect(options.nth(2)).toHaveAttribute("aria-selected", "true");
  await expect(options.nth(0)).toHaveAttribute("aria-selected", "false");

  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("ArrowUp");
  // Up from the first option goes to the last.
  await expect(editable).toHaveAttribute("aria-activedescendant", "post_body_editor-option-5");
  const label = (await options.nth(5).locator(".kotoba-menu-label").textContent()) ?? "";

  await page.keyboard.press("Enter");
  await expect(menu(page)).toBeHidden();
  await expect(editable.locator(".kotoba-mention")).toHaveText(label);
  await expect(editable).not.toHaveAttribute("aria-activedescendant", /.*/);

  const [mention] = await expectNodes(page, "mention", 1);
  expect(mention).toMatchObject({ kind: "people", label });
  // The caret is after the mention and a space.
  await page.keyboard.type("next");
  await expect(editable).toContainText(`${label} next`);
});

test("Tab also inserts the active option", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("@grace");
  await expect(listbox(page).getByRole("option")).toHaveCount(1);
  await page.keyboard.press("Tab");

  await expect(editable).toBeFocused();
  const [mention] = await expectNodes(page, "mention", 1);
  expect(mention).toMatchObject({ kind: "people", id: "3", label: "Grace Hopper" });
});

test("a query with no match shows No results", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("@zzz");

  await expect(menu(page).locator(".kotoba-menu-status")).toHaveText("No results");
  await expect(listbox(page)).toBeHidden();
  await expect(page.locator("#post_body_editor .kotoba-live")).toHaveText("No results");

  // Enter with no results is a new line, not a selection.
  await page.keyboard.press("Enter");
  await expectNodes(page, "paragraph", 2);
});

test("Escape closes the menu, and it stays closed for that trigger", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("@a");
  await expect(listbox(page)).toBeVisible();

  await page.keyboard.press("Escape");
  await expect(menu(page)).toBeHidden();
  await expect(editable).toBeFocused();

  await page.keyboard.type("d");
  await page.waitForTimeout(300);
  await expect(menu(page)).toBeHidden();

  // A new trigger opens the menu again.
  await page.keyboard.type(" @b");
  await expect(listbox(page).getByRole("option")).toHaveCount(1);
  await expect(listbox(page).getByRole("option")).toContainText("Barbara Liskov");
});

test("no menu in a code block or in the middle of a word", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("mail@example");
  await page.waitForTimeout(300);
  await expect(menu(page)).toBeHidden();

  await page.keyboard.press("Enter");
  await page.keyboard.type("``` ");
  await page.keyboard.type("@a");
  await page.waitForTimeout(300);
  await expect(menu(page)).toBeHidden();
});

test("a prompt whose callback fails shows No results, and the page stays alive", async ({ page }) => {
  const editable = await openEditor(page);
  // A server-side assign that a restart of the LiveView would reset.
  await page.locator("#push-changes").click();
  await expect(page.locator("#post_body_editor")).toHaveAttribute("data-change", "true");

  await editable.click();
  await page.keyboard.type("Hello ");
  await expect(page.locator("#change-count")).not.toHaveText("0");

  // The "!" prompt of the development page raises in its callback.
  await page.keyboard.type("!db");
  await expect(menu(page).locator(".kotoba-menu-status")).toHaveText("No results");
  await expect(page.locator("#post_body_editor .kotoba-live")).toHaveText("No results");
  const count = Number(await page.locator("#change-count").textContent());

  // The LiveView did not restart: it keeps its assigns and answers the next prompt.
  await expect(page.locator("[data-phx-main].phx-error")).toHaveCount(0);
  await expect(page.locator("#post_body_editor")).toHaveAttribute("data-change", "true");
  await expect(page.locator("#push-changes")).toBeChecked();
  await page.keyboard.type(" @grace");
  await expect(listbox(page).getByRole("option")).toHaveCount(1);
  await expect(editable).toContainText("Hello !db @grace");
  await expect.poll(async () => Number(await page.locator("#change-count").textContent())).toBeGreaterThan(count);
});
