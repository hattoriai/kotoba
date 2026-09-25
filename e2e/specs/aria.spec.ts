import { expect, test } from "@playwright/test";

import { MOD, openEditor, selectBack } from "./support";

test("the editor is a labelled, multi-line textbox", async ({ page }) => {
  await openEditor(page);
  const textbox = page.getByRole("textbox", { name: "Body" });
  await expect(textbox).toHaveAttribute("aria-multiline", "true");
  await expect(textbox).toHaveAttribute("aria-placeholder", "Write something…");
  await expect(textbox).toHaveAttribute("aria-autocomplete", "list");
  await expect(textbox).toHaveAttribute("aria-controls", "post_body_editor-menu");
  await expect(page.locator("#post_body_editor .kotoba-live")).toHaveAttribute("role", "status");
  await expect(page.locator("#post_body_editor .kotoba-live")).toHaveAttribute("aria-live", "polite");
});

test("the toolbar has groups and buttons with states", async ({ page }) => {
  await openEditor(page);
  const toolbar = page.getByRole("toolbar", { name: "Formatting" });
  for (const name of ["Text", "Blocks", "Lists", "Insert", "History"]) {
    await expect(toolbar.getByRole("group", { name })).toBeVisible();
  }
  await expect(toolbar.getByRole("button", { name: "Bold", exact: true })).toHaveAttribute("aria-pressed", "false");
  await expect(toolbar.getByRole("button", { name: "Heading 1" })).toHaveAttribute("aria-pressed", "false");
  await expect(toolbar.getByRole("button", { name: "Undo" })).toHaveAttribute("aria-disabled", "true");
  await expect(toolbar.getByRole("button", { name: "Attach a file" })).toHaveAttribute("aria-disabled", "false");
  await expect(toolbar.getByRole("button", { name: "Bold", exact: true })).toHaveAttribute("title", /Bold \((⌘|Ctrl\+)B\)/);
});

test("the prompt menu is a listbox with options and an active descendant", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("@a");

  const listbox = page.getByRole("listbox", { name: "people suggestions" });
  await expect(listbox).toHaveAttribute("id", "post_body_editor-menu");
  const options = listbox.getByRole("option");
  await expect(options).toHaveCount(6);
  await expect(editable).toHaveAttribute("aria-activedescendant", "post_body_editor-option-0");
  await expect(page.locator("#post_body_editor-option-0")).toHaveAttribute("aria-selected", "true");
  await expect(page.locator("#post_body_editor .kotoba-live")).toHaveText("6 results");
});

test("the link form is a dialog with a labelled input", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("text");
  await selectBack(page, 4);
  await page.keyboard.press(`${MOD}+K`);

  const dialog = page.getByRole("dialog", { name: "Link" });
  await expect(dialog.getByRole("textbox", { name: "URL" })).toBeFocused();
  await expect(dialog.getByRole("button", { name: "Apply" })).toBeVisible();
});

test("the upload input has a label for assistive technology", async ({ page }) => {
  await openEditor(page);
  const input = page.getByLabel("Attach files");
  await expect(input).toHaveAttribute("type", "file");
  await expect(input).toHaveAttribute("tabindex", "-1");
  await expect(input).toHaveAttribute("accept", ".png,.jpg,.jpeg,.gif,.webp,.pdf");
  // The editor's own picker is hidden from assistive technology; the
  // toolbar button opens it.
  await expect(page.locator("#post_body_editor .kotoba-file-picker")).toHaveAttribute("aria-hidden", "true");
});

test("a read-only editor says so", async ({ page }) => {
  await openEditor(page);
  await page.getByRole("button", { name: "Readonly" }).click();
  const textbox = page.getByRole("textbox", { name: "Body" });
  await expect(textbox).toHaveAttribute("aria-readonly", "true");
  await expect(page.getByRole("toolbar", { name: "Formatting" }).getByRole("button", { name: "Bold", exact: true })).toHaveAttribute("aria-disabled", "true");
});

test("a check list item is a checkbox", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("[] task");
  await expect(page.getByRole("checkbox", { name: "task" })).toHaveAttribute("aria-checked", "false");
});

test("the textbox follows the field's aria-invalid and aria-describedby", async ({ page }) => {
  const editable = await openEditor(page);
  await expect(editable).not.toHaveAttribute("aria-invalid", /.*/);
  await expect(editable).not.toHaveAttribute("aria-describedby", /.*/);

  await page.locator("#toggle-invalid").click();
  await expect(page.locator("#body-error")).toBeVisible();
  await expect(editable).toHaveAttribute("aria-invalid", "true");
  await expect(editable).toHaveAttribute("aria-describedby", "body-error");

  await page.locator("#toggle-invalid").click();
  await expect(page.locator("#body-error")).toHaveCount(0);
  await expect(editable).not.toHaveAttribute("aria-invalid", /.*/);
  await expect(editable).not.toHaveAttribute("aria-describedby", /.*/);
});
