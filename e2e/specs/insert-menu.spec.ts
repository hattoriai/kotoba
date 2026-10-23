import { expect, test, type Page } from "@playwright/test";

import { MOD, focusEnd, nodes, openEditor, readDocument, settle, type JSONNode } from "./support";

const EDITOR = "insert_editor";

/** The top-level blocks of a document: their type (the tag of a heading, the type of a list) and text. */
async function blocks(page: Page, inputId = "insert_body"): Promise<string[]> {
  const doc = await readDocument(page, inputId);
  const text = (node: JSONNode): string =>
    nodes(node)
      .map((child) => (typeof child.text === "string" ? child.text : child.type === "dev-tag" ? `#${String(child.label)}` : ""))
      .join("");
  return (doc.root.children ?? []).map((node) => {
    const type = node.type === "heading" ? String(node.tag) : node.type === "list" ? `${String(node.listType)}-list` : node.type;
    return `${type}: ${text(node)}`;
  });
}

const menu = (page: Page, editorId = EDITOR) => page.locator(`#${editorId}`).getByRole("listbox");
const options = (page: Page, editorId = EDITOR) => menu(page, editorId).getByRole("option");

/** A new line at the end of the editor, and the text typed in it. */
async function typeOnNewLine(page: Page, editorId: string, text: string): Promise<void> {
  await focusEnd(page, page.locator(`#${editorId} .kotoba-editable`));
  await page.keyboard.press("Enter");
  await page.keyboard.type(text);
  await settle(page);
}

test("the menu: the field's items, in groups, filtered as the person types", async ({ page }) => {
  await openEditor(page, "/insert", EDITOR);
  await typeOnNewLine(page, EDITOR, "/");

  await expect(menu(page)).toHaveAccessibleName("Insert");
  await expect(options(page)).toHaveText([
    "Text",
    "Heading 1",
    "Heading 2",
    "Heading 3",
    "Heading 4",
    "Quote",
    "Bulleted list",
    "Numbered list",
    "Check list",
    "Code block",
    "Table",
    "Divider",
    "Callout",
    "Tag",
    "Signature",
  ]);
  await expect(menu(page).getByRole("group", { name: "Basic" })).toBeVisible();
  await expect(menu(page).getByRole("group", { name: "The app's" })).toBeVisible();
  // No item of a feature the field does not have: no uploads, no embeds.
  await expect(menu(page).getByRole("option", { name: "Image or file" })).toHaveCount(0);

  await page.keyboard.type("h2");
  await expect(options(page)).toHaveText(["Heading 2"]);
  await page.keyboard.press("Backspace");
  await page.keyboard.press("Backspace");
  // Keywords find an item: "title" is Heading 1.
  await page.keyboard.type("title");
  await expect(options(page)).toHaveText(["Heading 1"]);
  await page.keyboard.press("Escape");
  await expect(menu(page)).toBeHidden();
});

test("an empty paragraph turns into the block, as one undo step", async ({ page }) => {
  await openEditor(page, "/insert", EDITOR);
  await typeOnNewLine(page, EDITOR, "/h2");
  await page.keyboard.press("Enter");
  await expect.poll(() => blocks(page)).toEqual(["paragraph: First paragraph", "h2: "]);
  await expect(page.locator(`#${EDITOR} .kotoba-live`)).toHaveText("Turned into Heading 2");
  await page.keyboard.type("Plan");
  await expect.poll(() => blocks(page)).toEqual(["paragraph: First paragraph", "h2: Plan"]);

  await typeOnNewLine(page, EDITOR, "/bul");
  await page.keyboard.press("Tab");
  await page.keyboard.type("One");
  await expect.poll(() => blocks(page)).toEqual(["paragraph: First paragraph", "h2: Plan", "bullet-list: One"]);

  // Undo takes the list back to "/bul", and not further.
  await page.keyboard.press(`${MOD}+z`);
  await page.keyboard.press(`${MOD}+z`);
  await expect.poll(() => blocks(page)).toEqual(["paragraph: First paragraph", "h2: Plan", "paragraph: /bul"]);
});

test("in a block with text, the block goes below; tables, dividers, the extension's and the app's items", async ({
  page,
}) => {
  await openEditor(page, "/insert", EDITOR);
  await focusEnd(page, page.locator(`#${EDITOR} .kotoba-editable`));
  await page.keyboard.type(" /quote");
  await page.keyboard.press("Enter");
  await page.keyboard.type("Said");
  await expect.poll(() => blocks(page)).toEqual(["paragraph: First paragraph ", "quote: Said"]);

  await typeOnNewLine(page, EDITOR, "/call");
  await page.keyboard.press("Enter");
  await page.keyboard.type("Careful");
  await expect.poll(async () => (await blocks(page)).at(-1)).toBe("dev-callout: Careful");

  await typeOnNewLine(page, EDITOR, "/table");
  await page.keyboard.press("Enter");
  await expect.poll(async () => (await blocks(page)).filter((block) => block.startsWith("table")).length).toBe(1);
  await page.keyboard.type("A");
  await expect.poll(async () => (await blocks(page)).find((block) => block.startsWith("table"))).toBe("table: A");

  await typeOnNewLine(page, EDITOR, "/divider");
  await page.keyboard.press("Enter");
  await page.keyboard.type("After");
  await expect.poll(async () => (await blocks(page)).slice(-2)).toEqual(["horizontalrule: ", "paragraph: After"]);

  // The app's items: a node, and a snippet.
  await page.keyboard.type(" /tag");
  await page.keyboard.press("Enter");
  await page.keyboard.type(" /sign");
  await page.keyboard.press("Enter");
  await expect.poll(async () => (await blocks(page)).at(-1)).toBe("paragraph: After #from the menu — Ada");
});

test("Markdown shortcuts stay, and the + of a block opens the menu", async ({ page }) => {
  const editable = await openEditor(page, "/insert", EDITOR);
  await typeOnNewLine(page, EDITOR, "## Shortcut");
  await expect.poll(() => blocks(page)).toEqual(["paragraph: First paragraph", "h2: Shortcut"]);

  const box = (await editable.locator(":scope > p").first().boundingBox())!;
  await page.mouse.move(box.x + 40, box.y + box.height / 2);
  await page.locator(`#${EDITOR} .kotoba-block-add`).click();
  await expect(menu(page)).toBeVisible();
  await page.keyboard.type("quote");
  await page.keyboard.press("Enter");
  await page.keyboard.type("Q");
  await expect.poll(() => blocks(page)).toEqual(["paragraph: First paragraph", "quote: Q", "h2: Shortcut"]);
});

test("a field with fewer features has fewer items, and with_text: :turn_into turns the block", async ({ page }) => {
  await openEditor(page, "/insert", "small_editor");
  await focusEnd(page, page.locator("#small_editor .kotoba-editable"));
  await page.keyboard.type(" /");
  await expect(options(page, "small_editor")).toHaveText(["Text", "Bulleted list", "Numbered list"]);
  await page.keyboard.type("num");
  await page.keyboard.press("Enter");
  await expect.poll(() => blocks(page, "small_body")).toEqual(["number-list: Some text "]);
});

test("an insert menu that the server searches", async ({ page }) => {
  await openEditor(page, "/insert", "search_editor");
  await page.locator("#search_editor .kotoba-editable").click();
  await page.keyboard.type("/tab");
  await expect(options(page, "search_editor")).toHaveText(["Table"]);
  await page.keyboard.press("Enter");
  await expect.poll(async () => (await blocks(page, "search_body")).map((block) => block.split(":")[0])).toContain("table");
});
