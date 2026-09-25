import { expect, test } from "@playwright/test";

import { MOD, expectNodes, nodesOfType, openEditor, selectBack } from "./support";

const BOLD = 1;
const ITALIC = 2;

test("typed text goes to the hidden input and to the server", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Hello, Kotoba");

  await expect(editable).toHaveText("Hello, Kotoba");
  const [text] = await expectNodes(page, "text", 1);
  expect(text?.text).toBe("Hello, Kotoba");

  // `kotoba:change` is debounced and then pushed once.
  await expect(page.locator("#change-count")).not.toHaveText("0");
});

test("the placeholder shows only while the editor is empty", async ({ page }) => {
  const editable = await openEditor(page);
  const placeholder = page.locator("#post_body_editor .kotoba-placeholder");
  await expect(placeholder).toBeVisible();
  await expect(placeholder).toHaveText("Write something…");

  await editable.click();
  await page.keyboard.type("x");
  await expect(placeholder).toBeHidden();
});

test("the toolbar buttons format the selection", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("plain bold");
  await selectBack(page, 4);

  const bold = page.getByRole("button", { name: "Bold", exact: true });
  await expect(bold).toHaveAttribute("aria-pressed", "false");
  await bold.click();

  await expect(editable.locator("strong.kotoba-bold")).toHaveText("bold");
  await expect(bold).toHaveAttribute("aria-pressed", "true");
  // The mouse press keeps the focus in the editor.
  await expect(editable).toBeFocused();

  await page.getByRole("button", { name: "Italic" }).click();
  await page.getByRole("button", { name: "Strikethrough" }).click();

  const texts = await nodesOfType(page, "text");
  expect(texts.map((node) => [node.text, node.format])).toEqual([
    ["plain ", 0],
    ["bold", BOLD | ITALIC | 4],
  ]);
});

test("Cmd/Ctrl+B and Cmd/Ctrl+I toggle bold and italic while typing", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("a ");
  await page.keyboard.press(`${MOD}+B`);
  await page.keyboard.type("bold");
  await page.keyboard.press(`${MOD}+B`);
  await page.keyboard.type(" ");
  await page.keyboard.press(`${MOD}+I`);
  await page.keyboard.type("italic");

  await expect(editable.locator("strong")).toHaveText("bold");
  await expect(editable.locator("em")).toHaveText("italic");
  await expect(page.getByRole("button", { name: "Italic" })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "Bold", exact: true })).toHaveAttribute("aria-pressed", "false");

  const texts = await expectNodes(page, "text", 4);
  expect(texts.map((node) => [node.text, node.format])).toEqual([
    ["a ", 0],
    ["bold", BOLD],
    [" ", 0],
    ["italic", ITALIC],
  ]);
});

test("the block buttons set headings and quotes", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Title");

  const h2 = page.getByRole("button", { name: "Heading 2" });
  await h2.click();
  await expect(editable.locator("h2.kotoba-h2")).toHaveText("Title");
  await expect(h2).toHaveAttribute("aria-pressed", "true");

  // The same button again makes it a paragraph.
  await h2.click();
  await expect(editable.locator("h2")).toHaveCount(0);

  await page.getByRole("button", { name: "Quote" }).click();
  await expect(editable.locator("blockquote")).toHaveText("Title");
  await expectNodes(page, "quote", 1);
});
