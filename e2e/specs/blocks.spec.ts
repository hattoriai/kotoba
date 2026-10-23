import { expect, test, type Locator, type Page } from "@playwright/test";

import { MOD, nodes, openEditor, readDocument, settle, type JSONNode } from "./support";

const EDITOR = "blocks_editor";
const INPUT = "blocks_body";

/** The top-level blocks of a document: their type (the tag of a heading) and text. */
async function blocks(page: Page, inputId = INPUT): Promise<string[]> {
  const doc = await readDocument(page, inputId);
  const text = (node: JSONNode): string =>
    nodes(node)
      .map((child) => (typeof child.text === "string" ? child.text : ""))
      .join("");
  return (doc.root.children ?? []).map((node) => {
    const type = node.type === "heading" ? String(node.tag) : node.type === "list" ? `${String(node.listType)}-list` : node.type;
    return `${type}: ${text(node)}`;
  });
}

const START = [
  "h1: Plan",
  "paragraph: First paragraph",
  "paragraph: Second paragraph",
  "bullet-list: OneTwo",
  "quote: A quote",
  "table: LanguageYearElixir2012",
];

const grip = (page: Page, editorId = EDITOR) => page.locator(`#${editorId} .kotoba-block-grip`);
const menu = (page: Page, editorId = EDITOR) => page.locator(`#${editorId}`).getByRole("menu", { name: "Block" });
const live = (page: Page, editorId = EDITOR) => page.locator(`#${editorId} .kotoba-live`);

/** The block of the editor with this text (its DOM element). */
function block(editable: Locator, text: string): Locator {
  return editable.locator(":scope > *").filter({ hasText: text }).first();
}

/** Moves the pointer over a block, and waits for its handle. */
async function hover(page: Page, editable: Locator, text: string): Promise<void> {
  const box = (await block(editable, text).boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await expect(grip(page)).toBeVisible();
  // The handle is beside the block, in the margin.
  await expect
    .poll(async () => {
      const handle = (await grip(page).boundingBox())!;
      return handle.x + handle.width <= box.x && handle.y < box.y + box.height && handle.y + handle.height > box.y;
    })
    .toBe(true);
}

/** Drags the grip of the block `text` to the pointer position `y`. */
async function dragTo(page: Page, editable: Locator, text: string, y: number): Promise<void> {
  await hover(page, editable, text);
  const handle = (await grip(page).boundingBox())!;
  await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2);
  await page.mouse.down();
  await page.mouse.move(handle.x + handle.width / 2, y, { steps: 8 });
  await expect(page.locator(`#${EDITOR} .kotoba-block-drop`)).toBeVisible();
  await page.mouse.up();
}

/** Puts the caret at the end of the block `text`. */
async function caretIn(page: Page, editable: Locator, text: string): Promise<void> {
  await block(editable, text).click();
  await page.keyboard.press("End");
  await settle(page);
}

test("a grip beside the block under the pointer, and no handles without the feature", async ({ page }) => {
  const editable = await openEditor(page, "/blocks", EDITOR);
  await expect.poll(() => blocks(page)).toEqual(START);

  await hover(page, editable, "Second paragraph");
  await hover(page, editable, "A quote");
  // A table has one handle, for the whole table.
  await hover(page, editable, "Elixir");

  // The editor without `blocks` is as it was: no margin, no handle.
  const none = page.locator("#none_editor");
  await expect(none).not.toHaveClass(/kotoba-has-blocks/);
  await expect(none.locator(".kotoba-block-handle")).toHaveCount(0);
  const plainPadding = await none.locator(".kotoba-editable").evaluate((element) => getComputedStyle(element).paddingLeft);
  const blocksPadding = await editable.evaluate((element) => getComputedStyle(element).paddingLeft);
  expect(Number.parseFloat(blocksPadding)).toBeGreaterThan(Number.parseFloat(plainPadding));

  // Its shortcuts do nothing.
  await none.locator(".kotoba-editable").getByText("One").click();
  await page.keyboard.press("Alt+Shift+ArrowDown");
  await page.keyboard.press(`${MOD}+/`);
  await expect(none.getByRole("menu")).toHaveCount(0);
  await expect.poll(() => blocks(page, "none_body")).toEqual(["paragraph: One", "paragraph: Two"]);
});

test("dragging the grip moves the block, in one undo step", async ({ page }) => {
  const editable = await openEditor(page, "/blocks", EDITOR);

  // The second paragraph, to above the first one.
  const first = (await block(editable, "First paragraph").boundingBox())!;
  await dragTo(page, editable, "Second paragraph", first.y + 2);
  await expect.poll(() => blocks(page)).toEqual([START[0], START[2], START[1], ...START.slice(3)]);
  await expect(live(page)).toHaveText("Block moved");

  // The list, to the end of the document.
  const table = (await block(editable, "Elixir").boundingBox())!;
  await dragTo(page, editable, "One", table.y + table.height - 2);
  await expect.poll(() => blocks(page)).toEqual([START[0], START[2], START[1], START[4], START[5], START[3]]);

  // Each move is one step of the history.
  await editable.focus();
  await page.keyboard.press(`${MOD}+z`);
  await expect.poll(() => blocks(page)).toEqual([START[0], START[2], START[1], ...START.slice(3)]);
  await page.keyboard.press(`${MOD}+z`);
  await expect.poll(() => blocks(page)).toEqual(START);
});

test("a drag that comes back, or is called off with Escape, moves nothing", async ({ page }) => {
  const editable = await openEditor(page, "/blocks", EDITOR);
  await hover(page, editable, "Second paragraph");
  const handle = (await grip(page).boundingBox())!;
  const first = (await block(editable, "First paragraph").boundingBox())!;

  await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2);
  await page.mouse.down();
  await page.mouse.move(handle.x + handle.width / 2, first.y + 2, { steps: 6 });
  await expect(page.locator(`#${EDITOR} .kotoba-block-drop`)).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator(`#${EDITOR} .kotoba-block-drop`)).toBeHidden();
  await page.mouse.up();
  await expect(menu(page)).toBeHidden();
  expect(await blocks(page)).toEqual(START);
});

test("the keyboard moves the block at the caret, and the caret goes with it", async ({ page }) => {
  const editable = await openEditor(page, "/blocks", EDITOR);
  await caretIn(page, editable, "First paragraph");

  await page.keyboard.press("Alt+Shift+ArrowDown");
  await expect.poll(() => blocks(page)).toEqual([START[0], START[2], START[1], ...START.slice(3)]);
  await expect(live(page)).toHaveText("Block moved down");
  await page.keyboard.press("Alt+Shift+ArrowDown");
  await expect.poll(() => blocks(page)).toEqual([START[0], START[2], START[3], START[1], ...START.slice(4)]);

  // The caret is still at the end of the block.
  await page.keyboard.type("!");
  await expect.poll(() => blocks(page)).toContain("paragraph: First paragraph!");

  await page.keyboard.press("Alt+Shift+ArrowUp");
  await page.keyboard.press("Alt+Shift+ArrowUp");
  await page.keyboard.press("Alt+Shift+ArrowUp");
  await expect.poll(async () => (await blocks(page))[0]).toBe("paragraph: First paragraph!");
  await page.keyboard.press("Alt+Shift+ArrowUp");
  await expect(live(page)).toHaveText("The block is the first");

  // A list item moves its whole list.
  await caretIn(page, editable, "Two");
  await page.keyboard.press("Alt+Shift+ArrowUp");
  await expect.poll(() => blocks(page)).toEqual([
    "paragraph: First paragraph!",
    START[0],
    START[3],
    START[2],
    START[4],
    START[5],
  ]);
});

test("the menu, from the keyboard: Turn into, and Escape gives the caret back", async ({ page }) => {
  const editable = await openEditor(page, "/blocks", EDITOR);
  await caretIn(page, editable, "First paragraph");

  await page.keyboard.press(`${MOD}+/`);
  await expect(menu(page)).toBeVisible();
  await expect(grip(page)).toHaveAttribute("aria-expanded", "true");
  const items = menu(page).locator("[role^=menuitem]");
  await expect(items).toHaveText([
    "Paragraph",
    "Heading 1",
    "Heading 2",
    "Heading 3",
    "Heading 4",
    "Quote",
    "Bulleted list",
    "Numbered list",
    "Check list",
    "Code block",
    "Callout",
    "Duplicate",
    "Delete",
    "Copy a link to the block",
  ]);
  await expect(menu(page).getByRole("group", { name: "Turn into" })).toBeVisible();
  await expect(menu(page).getByRole("menuitemradio", { name: "Paragraph" })).toHaveAttribute("aria-checked", "true");
  await expect(items.first()).toBeFocused();

  // Escape: the menu closes, the caret is where it was.
  await page.keyboard.press("Escape");
  await expect(menu(page)).toBeHidden();
  await expect(editable).toBeFocused();
  await page.keyboard.type("!");
  await expect.poll(() => blocks(page)).toContain("paragraph: First paragraph!");

  // Down twice to Heading 2, and Enter.
  await page.keyboard.press(`${MOD}+/`);
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("ArrowDown");
  await expect(menu(page).getByRole("menuitemradio", { name: "Heading 2" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect.poll(() => blocks(page)).toEqual([START[0], "h2: First paragraph!", ...START.slice(2)]);
  await expect(live(page)).toHaveText("Turned into Heading 2");
  await expect(editable).toBeFocused();
  // The caret stayed in the block.
  await page.keyboard.type("?");
  await expect.poll(() => blocks(page)).toContain("h2: First paragraph!?");

  // Up from the first item goes to the last one; Tab leaves the menu.
  await page.keyboard.press(`${MOD}+/`);
  await expect(menu(page).getByRole("menuitemradio", { name: "Heading 2" })).toHaveAttribute("aria-checked", "true");
  await page.keyboard.press("ArrowUp");
  await expect(menu(page).getByRole("menuitem", { name: "Copy a link to the block" })).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(menu(page)).toBeHidden();
});

test("Turn into with the pointer: lists, the extension's callout, and back", async ({ page }) => {
  const editable = await openEditor(page, "/blocks", EDITOR);

  await hover(page, editable, "Second paragraph");
  await grip(page).click();
  await menu(page).getByRole("menuitemradio", { name: "Numbered list" }).click();
  await expect.poll(() => blocks(page)).toEqual([...START.slice(0, 2), "number-list: Second paragraph", ...START.slice(3)]);

  // A list turns into a paragraph as a whole.
  await hover(page, editable, "One");
  await grip(page).click();
  await expect(menu(page).getByRole("menuitemradio", { name: "Bulleted list" })).toHaveAttribute("aria-checked", "true");
  await menu(page).getByRole("menuitemradio", { name: "Paragraph" }).click();
  await expect.poll(() => blocks(page)).toEqual([
    ...START.slice(0, 2),
    "number-list: Second paragraph",
    "paragraph: One",
    "paragraph: Two",
    ...START.slice(4),
  ]);

  await hover(page, editable, "A quote");
  await grip(page).click();
  await menu(page).getByRole("menuitemradio", { name: "Callout" }).click();
  await expect.poll(async () => (await blocks(page)).includes("dev-callout: A quote")).toBe(true);
  await expect(editable.locator("aside.dev-callout")).toHaveText("A quote");

  await hover(page, editable, "A quote");
  await grip(page).click();
  await expect(menu(page).getByRole("menuitemradio", { name: "Callout" })).toHaveAttribute("aria-checked", "true");
  await menu(page).getByRole("menuitemradio", { name: "Heading 3" }).click();
  await expect.poll(async () => (await blocks(page)).includes("h3: A quote")).toBe(true);

  // A table is not a block of text: it has no Turn into.
  await hover(page, editable, "Elixir");
  await grip(page).click();
  await expect(menu(page).locator("[role^=menuitem]")).toHaveText(["Duplicate", "Delete", "Copy a link to the block"]);
  // The grip closes its menu again.
  await grip(page).click();
  await expect(menu(page)).toBeHidden();
  await expect(grip(page)).toHaveAttribute("aria-expanded", "false");
});

test("Duplicate, Delete, the + and Copy a link", async ({ page }) => {
  await page.addInitScript(() => {
    const copied: string[] = [];
    (window as unknown as { copied: string[] }).copied = copied;
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText: (text: string) => (copied.push(text), Promise.resolve()) },
    });
  });
  const editable = await openEditor(page, "/blocks", EDITOR);

  await hover(page, editable, "A quote");
  await grip(page).click();
  await menu(page).getByRole("menuitem", { name: "Duplicate" }).click();
  await expect.poll(() => blocks(page)).toEqual([...START.slice(0, 5), START[4], START[5]]);
  await expect(live(page)).toHaveText("Block duplicated");

  await hover(page, editable, "Elixir");
  await grip(page).click();
  await menu(page).getByRole("menuitem", { name: "Duplicate" }).click();
  await expect.poll(() => blocks(page)).toEqual([...START.slice(0, 5), START[4], START[5], START[5]]);

  await hover(page, editable, "Elixir");
  await grip(page).click();
  await menu(page).getByRole("menuitem", { name: "Delete" }).click();
  await expect.poll(() => blocks(page)).toEqual([...START.slice(0, 5), START[4], START[5]]);
  await expect(live(page)).toHaveText("Block deleted");

  // The + adds a paragraph below the block, with the caret in it.
  await hover(page, editable, "Plan");
  await page.locator(`#${EDITOR} .kotoba-block-add`).click();
  await page.keyboard.type("New");
  await expect.poll(async () => (await blocks(page)).slice(0, 3)).toEqual([START[0], "paragraph: New", START[1]]);

  await hover(page, editable, "Second paragraph");
  await grip(page).click();
  await menu(page).getByRole("menuitem", { name: "Copy a link to the block" }).click();
  await expect(live(page)).toHaveText("Link copied");
  const copied = await page.evaluate(() => (window as unknown as { copied: string[] }).copied);
  expect(copied).toEqual([`${new URL("/blocks", page.url()).href}#:~:text=Second%20paragraph`]);
});

test("the menu offers the editor's features only", async ({ page }) => {
  await openEditor(page, "/blocks", "plain_editor");
  const editable = page.locator("#plain_editor .kotoba-editable");
  await editable.getByText("Two").click();
  await page.keyboard.press(`${MOD}+/`);
  await expect(menu(page, "plain_editor").locator("[role^=menuitem]")).toHaveText([
    "Paragraph",
    "Bulleted list",
    "Numbered list",
    "Duplicate",
    "Delete",
    "Copy a link to the block",
  ]);
  await page.keyboard.press("Escape");
});

test("in a shared editor, a move reaches the others, their caret goes with the block, and undo takes it back", async ({
  page,
  context,
}) => {
  const other = await context.newPage();
  const id = crypto.randomUUID();
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  other.on("pageerror", (error) => errors.push(error.message));
  const shared = (on: Page) => on.locator("#shared_editor .kotoba-editable");
  for (const [on, name] of [
    [page, "Ada"],
    [other, "Grace"],
  ] as const) {
    await openEditor(on, `/collab?document=${id}&name=${name}&blocks=true`, "shared_editor");
    await expect(on.locator("#shared_editor [data-collab-status]")).toHaveText("Saved");
  }
  const paragraphs = (on: Page) => shared(on).locator(":scope > p");

  await shared(page).click();
  await page.keyboard.type("One");
  await page.keyboard.press("Enter");
  await page.keyboard.type("Two");
  await page.keyboard.press("Enter");
  await page.keyboard.type("Three");
  await expect(paragraphs(other)).toHaveText(["One", "Two", "Three"]);

  // Grace's caret is at the end of "One".
  await paragraphs(other).first().click();
  await other.keyboard.press("End");
  await settle(other);

  // Ada moves "One" to the end, with the grip.
  const box = (await paragraphs(page).first().boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  const handle = page.locator("#shared_editor .kotoba-block-grip");
  await expect(handle).toBeVisible();
  const at = (await handle.boundingBox())!;
  const last = (await paragraphs(page).last().boundingBox())!;
  await page.mouse.move(at.x + at.width / 2, at.y + at.height / 2);
  await page.mouse.down();
  await page.mouse.move(at.x + at.width / 2, last.y + last.height - 1, { steps: 8 });
  await page.mouse.up();
  await expect(paragraphs(page)).toHaveText(["Two", "Three", "One"]);
  await expect(paragraphs(other)).toHaveText(["Two", "Three", "One"]);

  // Grace types where her caret was: at the end of "One".
  await other.keyboard.type("!");
  await expect(paragraphs(page)).toHaveText(["Two", "Three", "One!"]);

  // Ada's undo takes back her move, and keeps Grace's "!".
  await shared(page).focus();
  await page.keyboard.press(`${MOD}+Z`);
  await expect(paragraphs(other)).toHaveText(["One!", "Two", "Three"]);

  // Grace moves it down with the keyboard.
  await other.keyboard.press("Alt+Shift+ArrowDown");
  await expect(paragraphs(page)).toHaveText(["Two", "One!", "Three"]);
  expect(errors).toEqual([]);
});

test("a read-only editor has no handles", async ({ page }) => {
  const id = crypto.randomUUID();
  await openEditor(page, `/collab?document=${id}&name=Ada&role=read&blocks=true`, "shared_editor");
  await expect(page.locator("#shared_editor [data-collab-status]")).toHaveText("Live view");
  const box = (await page.locator("#shared_editor .kotoba-editable").boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + 10);
  await expect(page.locator("#shared_editor .kotoba-block-grip")).toBeHidden();
});
