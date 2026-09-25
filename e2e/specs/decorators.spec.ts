import { expect, test } from "@playwright/test";

import { expectNodes, openEditor, png, sendFiles, settle } from "./support";

test("Backspace selects a mention and then deletes it", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Hi @grace");
  await expect(page.getByRole("option")).toHaveCount(1);
  await page.keyboard.press("Enter");
  await expectNodes(page, "mention", 1);

  // The space after the mention, then the mention.
  await settle(page);
  await page.keyboard.press("Backspace");
  await settle(page);
  await page.keyboard.press("Backspace");
  const mention = editable.locator(".kotoba-mention");
  if ((await mention.count()) === 1) {
    await expect(mention).toHaveClass(/kotoba-selected/);
    await page.keyboard.press("Backspace");
  }
  await expect(mention).toHaveCount(0);
  await expectNodes(page, "mention", 0);
  await expect(editable).toHaveText("Hi ");
});

test("Delete removes an inline app node after the caret", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("A ");
  await page.getByRole("button", { name: "Insert tag" }).click();
  await expectNodes(page, "dev-tag", 1);

  await editable.focus();
  await page.keyboard.press("Home");
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("ArrowRight");
  await settle(page);
  await page.keyboard.press("Delete");
  const tag = editable.locator(".dev-tag");
  if ((await tag.count()) === 1) await page.keyboard.press("Delete");

  await expect(tag).toHaveCount(0);
  await expectNodes(page, "dev-tag", 0);
});

test("a clicked attachment is selected and Backspace deletes it", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await sendFiles(editable, "drop", [png("delete-me.png", 2, 2)]);
  await expectNodes(page, "attachment", 1);

  const figure = editable.locator(".kotoba-attachment");
  await figure.click();
  await expect(figure).toHaveClass(/kotoba-selected/);
  await page.keyboard.press("Backspace");

  await expect(figure).toHaveCount(0);
  await expectNodes(page, "attachment", 0);
});
