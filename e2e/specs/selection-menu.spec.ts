import { expect, test, type Page } from "@playwright/test";

import { MOD, expectNodes, openEditor, selectBack, settle } from "./support";

const menu = (page: Page) => page.getByRole("toolbar", { name: "Selection formatting" });
const card = (page: Page) => page.getByRole("toolbar", { name: "Link" });

test("an editor with no selection menu shows none", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Plain words");
  await selectBack(page, 5);
  await expect(page.locator(".kotoba-selection-menu")).toHaveCount(0);
});

test("the selection menu shows over selected text and formats it", async ({ page }) => {
  const editable = await openEditor(page, "/?menu=default");
  await editable.click();
  await page.keyboard.press("Enter");
  await page.keyboard.type("Make this bold");
  await expect(menu(page)).toBeHidden();

  await selectBack(page, 4);
  await expect(menu(page)).toBeVisible();

  // Above the selected text, as there is room there.
  const selection = await page.evaluate(() => window.getSelection()!.getRangeAt(0).getBoundingClientRect().top);
  const box = (await menu(page).boundingBox())!;
  expect(box.y + box.height).toBeLessThanOrEqual(selection);
  await expect(menu(page)).toHaveAttribute("data-placement", "top");

  const bold = menu(page).getByRole("button", { name: "Bold" });
  await bold.click();
  await expect(editable.locator("strong")).toHaveText("bold");
  await expect(bold).toHaveAttribute("aria-pressed", "true");
  await expect(menu(page)).toBeVisible();

  // A caret is not a selection.
  await page.keyboard.press("ArrowRight");
  await expect(menu(page)).toBeHidden();
});

test("the selection menu has the editor's commands only", async ({ page }) => {
  const editable = await openEditor(page, "/?menu=default");
  await editable.click();
  await page.keyboard.type("Some words");
  await selectBack(page, 5);
  await expect(menu(page)).toBeVisible();
  const names = await menu(page).getByRole("button").evaluateAll((buttons) =>
    buttons.map((button) => button.getAttribute("aria-label")),
  );
  expect(names).toEqual(["Bold", "Italic", "Underline", "Strikethrough", "Inline code", "Highlight", "Link"]);
});

test("Alt+F10 moves the focus to the menu, and Escape closes it", async ({ page }) => {
  const editable = await openEditor(page, "/?menu=default");
  await editable.click();
  await page.keyboard.type("Keyboard words");
  await selectBack(page, 5);
  await expect(menu(page)).toBeVisible();

  await page.keyboard.press("Alt+F10");
  await expect(menu(page).getByRole("button", { name: "Bold" })).toBeFocused();
  await page.keyboard.press("ArrowRight");
  await expect(menu(page).getByRole("button", { name: "Italic" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(editable.locator("em")).toHaveText("words");

  await page.keyboard.press("Escape");
  await expect(menu(page)).toBeHidden();
  await expect(editable).toBeFocused();

  // A new selection shows it again.
  await selectBack(page, 2);
  await expect(menu(page)).toBeVisible();
});

test("the menu's link button opens the link form", async ({ page }) => {
  const editable = await openEditor(page, "/?menu=default");
  await editable.click();
  await page.keyboard.type("Read the docs");
  await selectBack(page, 4);
  await menu(page).getByRole("button", { name: "Link" }).click();

  const form = page.getByRole("dialog", { name: "Link" });
  await expect(form).toBeVisible();
  await expect(menu(page)).toBeHidden();
  await form.getByLabel("URL").fill("https://hexdocs.pm");
  await page.keyboard.press("Enter");
  await expect(editable.locator("a")).toHaveAttribute("href", "https://hexdocs.pm");
});

test("the menu does not show in a code block", async ({ page }) => {
  const editable = await openEditor(page, "/?menu=default");
  await editable.click();
  await page.keyboard.type("```");
  await page.keyboard.press("Enter");
  await page.keyboard.type("let x = 1");
  await selectBack(page, 5);
  await settle(page);
  await expect(menu(page)).toBeHidden();
});

test("an app's own selection menu", async ({ page }) => {
  const editable = await openEditor(page, "/?menu=custom");
  await editable.click();
  await page.keyboard.type("Custom menu");
  await selectBack(page, 4);

  const custom = page.getByRole("toolbar", { name: "Quick format" });
  await expect(custom).toBeVisible();
  await expect(custom).toHaveClass(/custom-menu/);
  await custom.getByRole("button", { name: "Heading" }).click();
  await expectNodes(page, "heading", 1);
});

test("the link card shows the URL of the link at the caret, and edits or removes it", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Read the docs");
  await selectBack(page, 4);
  await page.keyboard.press(`${MOD}+K`);
  await page.keyboard.type("https://hexdocs.pm");
  await page.keyboard.press("Enter");
  await expect(editable.locator("a")).toHaveCount(1);

  await editable.locator("a").click();
  await expect(card(page)).toBeVisible();
  const open = card(page).getByRole("link", { name: "Open https://hexdocs.pm in a new tab" });
  await expect(open).toHaveAttribute("href", "https://hexdocs.pm");
  await expect(open).toHaveAttribute("target", "_blank");

  // Escape closes it until the caret moves.
  await page.keyboard.press("Escape");
  await expect(card(page)).toBeHidden();
  await page.keyboard.press("ArrowLeft");
  await expect(card(page)).toBeVisible();

  await card(page).getByRole("button", { name: "Edit link" }).click();
  const form = page.getByRole("dialog", { name: "Link" });
  await expect(form.getByLabel("URL")).toHaveValue("https://hexdocs.pm");
  await form.getByLabel("URL").fill("https://elixir-lang.org");
  await page.keyboard.press("Enter");
  await expect(editable.locator("a")).toHaveAttribute("href", "https://elixir-lang.org");

  await editable.locator("a").click();
  await card(page).getByRole("button", { name: "Remove link" }).click();
  await expect(editable.locator("a")).toHaveCount(0);
  await expect(editable).toHaveText("Read the docs");
  await expect(editable).toBeFocused();
});

test("the link card is keyboard reachable with Alt+F10", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Go home");
  await selectBack(page, 4);
  await page.keyboard.press(`${MOD}+K`);
  await page.keyboard.type("/home");
  await page.keyboard.press("Enter");
  await editable.locator("a").click();
  await expect(card(page)).toBeVisible();

  await page.keyboard.press("Alt+F10");
  await expect(card(page).getByRole("link")).toBeFocused();
  await page.keyboard.press("ArrowRight");
  await expect(card(page).getByRole("button", { name: "Edit link" })).toBeFocused();
});
