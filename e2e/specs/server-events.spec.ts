import { expect, test } from "@playwright/test";

import { expectNodes, focusEnd, openEditor } from "./support";

test("set_content replaces the document and is not pushed back", async ({ page }) => {
  const editable = await openEditor(page);
  await page.getByRole("button", { name: "Load sample" }).click();

  await expect(editable.locator("h2")).toHaveText("Sample");
  await expect(editable.locator("strong")).toHaveText("server");
  await expect(editable.locator(".dev-tag")).toHaveText("sample");
  await expect(editable.locator(".kotoba-mention")).toHaveText("Ada Lovelace");
  await expect(editable.locator("ul li")).toHaveText("One");
  await expectNodes(page, "dev-tag", 1);

  await page.waitForTimeout(500);
  await expect(page.locator("#change-count")).toHaveText("0");
});

test("insert_node puts a node at the selection", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Status: ");
  await page.getByRole("button", { name: "Insert tag" }).click();

  await expect(editable.locator(".dev-tag")).toHaveText("urgent");
  await expect(editable.locator("p")).toHaveText("Status: urgent");
  const [tag] = await expectNodes(page, "dev-tag", 1);
  expect(tag).toMatchObject({ label: "urgent", version: 1 });
});

test("set_readonly locks and unlocks the editor", async ({ page }) => {
  const editable = await openEditor(page);
  await page.getByRole("button", { name: "Lock (push)", exact: true }).click();

  await expect(editable).toHaveAttribute("contenteditable", "false");
  await expect(editable).toHaveAttribute("aria-readonly", "true");
  const buttons = page.locator("#post_body_editor [role=toolbar] button");
  for (const button of await buttons.all()) await expect(button).toHaveAttribute("aria-disabled", "true");

  await page.getByRole("button", { name: "Unlock (push)", exact: true }).click();
  await expect(editable).toHaveAttribute("contenteditable", "true");
  await expect(editable).not.toHaveAttribute("aria-readonly", /.*/);
  await expect(page.getByRole("button", { name: "Bold", exact: true })).toHaveAttribute("aria-disabled", "false");

  await focusEnd(page, editable);
  await page.keyboard.type("typed");
  await expect(editable).toHaveText("typed");
});

test("a readonly assign reaches the editor through updated()", async ({ page }) => {
  const editable = await openEditor(page);
  const toggle = page.getByRole("button", { name: "Readonly" });

  await toggle.click();
  await expect(toggle).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator("#post_body_editor")).toHaveAttribute("data-readonly", "true");
  await expect(editable).toHaveAttribute("contenteditable", "false");

  await editable.click();
  await page.keyboard.type("nothing");
  await expect(editable).toHaveText("");

  await toggle.click();
  await expect(editable).toHaveAttribute("contenteditable", "true");
});

test("a patch with the same readonly value does not undo set_readonly", async ({ page }) => {
  const editable = await openEditor(page);
  await page.getByRole("button", { name: "Lock (push)", exact: true }).click();
  await expect(editable).toHaveAttribute("contenteditable", "false");

  // A patch of the LiveView (a phx-change) keeps data-readonly="false".
  await page.locator("#post_body").evaluate((input) => input.dispatchEvent(new Event("input", { bubbles: true })));
  await expect(page.locator("#validate-count")).toHaveText("1");
  await expect(editable).toHaveAttribute("contenteditable", "false");
});

test("focus moves the focus to the editor", async ({ page }) => {
  const editable = await openEditor(page);
  await page.getByRole("button", { name: "Focus editor" }).click();
  await expect(editable).toBeFocused();
});
