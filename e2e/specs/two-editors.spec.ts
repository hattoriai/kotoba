import { expect, test } from "@playwright/test";

import { expectNodes, openEditor } from "./support";

test("a push names its editor, and the other editor ignores it", async ({ page }) => {
  const first = await openEditor(page, "/two", "a_editor");
  const second = page.locator("#b_editor .kotoba-editable");
  await expect(second).toHaveAttribute("contenteditable", "true");

  await page.getByRole("button", { name: "Load the first editor" }).click();
  await expect(first.locator("h2")).toHaveText("First");
  await page.waitForTimeout(300);
  await expect(second).toHaveText("");

  await page.getByRole("button", { name: "Load the second editor" }).click();
  await expect(second.locator("h2")).toHaveText("Second");
  await expect(first.locator("h2")).toHaveText("First");
  await expectNodes(page, "heading", 1, "a_body");
  await expectNodes(page, "heading", 1, "b_body");
});

test("an editor with phx-target sends its events to the LiveComponent", async ({ page }) => {
  const first = await openEditor(page, "/two", "a_editor");
  const second = page.locator("#b_editor .kotoba-editable");
  await expect(page.locator("#b_editor")).toHaveAttribute("phx-target", /.+/);

  await second.click();
  await page.keyboard.type("in the component");
  await expect(page.locator("#panel-changes")).not.toHaveText("0");
  await expect(page.locator("#parent-changes")).toHaveText("");

  // The prompt goes to the component too, and its results come back.
  await page.keyboard.type(" @ada");
  await expect(page.locator("#b_editor").getByRole("option")).toHaveText(/Ada Lovelace/);
  // The prompt of this editor has a label, which names its menu.
  await expect(page.locator("#b_editor").getByRole("listbox", { name: "People in the workshop" })).toBeVisible();
  await page.keyboard.press("Enter");
  await expectNodes(page, "mention", 1, "b_body");

  await first.click();
  await page.keyboard.type("in the view");
  await expect(page.locator("#parent-changes")).toHaveText("a_editor");
});
