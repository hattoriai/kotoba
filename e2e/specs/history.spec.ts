import { expect, test } from "@playwright/test";

import { MOD, nodesOfType, openEditor } from "./support";

test("Cmd/Ctrl+Z right after mount keeps the loaded document", async ({ page }) => {
  const editable = await openEditor(page, "/?sample=1");
  await expect(editable.locator("h2")).toHaveText("Initial");

  const undo = page.getByRole("button", { name: "Undo" });
  await expect(undo).toHaveAttribute("aria-disabled", "true");

  await editable.focus();
  await page.keyboard.press(`${MOD}+Z`);
  await page.keyboard.press(`${MOD}+Z`);

  await expect(editable.locator("h2")).toHaveText("Initial");
  await expect(editable.locator(".dev-tag")).toHaveText("sample");
});

test("undo and redo, from the keyboard and the toolbar", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("First");
  // History merges changes that come within 300 ms.
  await page.waitForTimeout(400);
  await page.keyboard.type(" second");
  await expect(editable).toHaveText("First second");

  const undo = page.getByRole("button", { name: "Undo" });
  const redo = page.getByRole("button", { name: "Redo" });
  await expect(undo).toHaveAttribute("aria-disabled", "false");
  await expect(redo).toHaveAttribute("aria-disabled", "true");

  await page.keyboard.press(`${MOD}+Z`);
  await expect(editable).toHaveText("First");
  await expect(redo).toHaveAttribute("aria-disabled", "false");

  await page.keyboard.press(`${MOD}+Shift+Z`);
  await expect(editable).toHaveText("First second");

  await undo.click();
  await expect(editable).toHaveText("First");
  await redo.click();
  await expect(editable).toHaveText("First second");

  const texts = await nodesOfType(page, "text");
  expect(texts.map((node) => node.text)).toEqual(["First second"]);
});

test("set_content clears the history", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("typed before");
  await page.getByRole("button", { name: "Load sample" }).click();
  await expect(editable.locator("h2")).toHaveText("Sample");
  await expect(page.getByRole("button", { name: "Undo" })).toHaveAttribute("aria-disabled", "true");

  await editable.focus();
  await page.keyboard.press(`${MOD}+Z`);
  await expect(editable.locator("h2")).toHaveText("Sample");
  await expect(editable).not.toContainText("typed before");
});
