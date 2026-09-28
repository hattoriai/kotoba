import { expect, test, type Page } from "@playwright/test";

import { collectConsole, expectNodes, nodesOfType, openEditor, pasteData, readDocument, settle } from "./support";

const COMMENT = "comment_editor";
const toolbar = (page: Page, editorId = COMMENT) => page.locator(`#${editorId}`).getByRole("toolbar", { name: "Formatting" });
const buttons = (page: Page, editorId = COMMENT) =>
  toolbar(page, editorId).locator("[data-kotoba-command]:visible");

async function paste(page: Page, editorId: string, html: string): Promise<void> {
  await pasteData(page, page.locator(`#${editorId} .kotoba-editable`), { html, text: "pasted" });
}

/** The types of the top-level nodes of an editor's document. */
async function blocks(page: Page, inputId = "comment_body"): Promise<string[]> {
  return (await readDocument(page, inputId)).root.children?.map((node) => node.type) ?? [];
}

test("an editor has only its features: toolbar, shortcuts and formats", async ({ page }) => {
  const editable = await openEditor(page, "/extensions", COMMENT);

  await expect
    .poll(() => buttons(page).evaluateAll((all) => all.map((button) => button.getAttribute("aria-label"))))
    .toEqual(["Bold", "Italic", "Link", "Bulleted list", "Numbered list", "Callout", "Undo", "Redo"]);
  // The editor with every feature has them all, and not the extension.
  await expect(toolbar(page, "notes_editor").getByRole("button", { name: "Table" })).toBeVisible();
  await expect(toolbar(page, "notes_editor").getByRole("button", { name: "Callout" })).toHaveCount(0);

  await editable.click();
  for (const line of ["# not a heading", "> not a quote", "``` not code", "~~not struck~~ `not code`"]) {
    await page.keyboard.type(line);
    await page.keyboard.press("Enter");
  }
  await page.keyboard.type("*italic* **bold**");
  await page.keyboard.press("Enter");
  await page.keyboard.type("- [ ] a bullet, not a check");

  await expect.poll(() => blocks(page)).toEqual(["paragraph", "paragraph", "paragraph", "paragraph", "paragraph", "list"]);
  const texts = await nodesOfType(page, "text", "comment_body");
  expect(texts.filter((node) => node.format !== 0).map((node) => [node.text, node.format])).toEqual([
    ["italic", 2],
    ["bold", 1],
  ]);
  const [list] = await nodesOfType(page, "list", "comment_body");
  expect(list?.listType).toBe("bullet");
});

test("pasted content of a feature that is off comes in as paragraphs and text", async ({ page }) => {
  const editable = await openEditor(page, "/extensions", COMMENT);
  const html =
    "<h2>Title</h2><table><tr><td>A</td><td>B</td></tr></table>" +
    "<pre><code>code()</code></pre><p><s>struck</s> <b>bold</b></p>";

  await editable.click();
  await paste(page, COMMENT, html);
  await expect.poll(async () => JSON.stringify((await readDocument(page, "comment_body")).root)).toContain("code()");
  // Every block is a paragraph: no heading, table or code block.
  expect(new Set(await blocks(page))).toEqual(new Set(["paragraph"]));
  const formats = (await nodesOfType(page, "text", "comment_body")).map((node) => [node.text, node.format]);
  expect(formats).toContainEqual(["bold", 1]);
  expect(formats.some(([, format]) => format === 4)).toBe(false);

  // The editor with every feature keeps them.
  await page.locator("#notes_editor .kotoba-editable").click();
  await paste(page, "notes_editor", html);
  await expect.poll(() => blocks(page, "notes_body")).toContain("table");
  expect(await blocks(page, "notes_body")).toEqual(expect.arrayContaining(["heading", "table", "code"]));
});

test("a stored node of a feature that is off is kept, and the server refuses it", async ({ page }) => {
  const editable = await openEditor(page, "/extensions", COMMENT);
  await page.getByRole("button", { name: "Load the sample" }).click();

  // The heading and the table are unknown nodes in this editor: shown, kept.
  await expect(editable.locator(".kotoba-unknown")).not.toHaveCount(0);
  await expect(editable.locator("ul li")).toHaveText("One");
  await expect.poll(() => blocks(page)).toEqual(["heading", "paragraph", "list", "table"]);

  await page.getByRole("button", { name: "Save" }).click();
  await expect(page.locator("#comment-error")).toHaveText("has content that is not allowed: headings, tables, mentions");
});

test("a document with the editor's features is saved", async ({ page }) => {
  const editable = await openEditor(page, "/extensions", COMMENT);
  await editable.click();
  await page.keyboard.type("Just a comment");
  await expectNodes(page, "text", 1, "comment_body");

  await page.getByRole("button", { name: "Save" }).click();
  await expect(page.locator("#comment-saved")).toHaveText("Just a comment");
  await expect(page.locator("#comment-error")).toHaveCount(0);
});

test("the example extension: its node, its command, its button and its Markdown shortcut", async ({ page }) => {
  const editable = await openEditor(page, "/extensions", COMMENT);
  const callout = toolbar(page).getByRole("button", { name: "Callout" });
  await expect(callout).toHaveAttribute("aria-pressed", "false");

  await editable.click();
  await page.keyboard.type("Mind the gap");
  await callout.click();
  await expect(editable.locator("aside.dev-callout")).toHaveText("Mind the gap");
  await expect(callout).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator(`#${COMMENT} .kotoba-live`)).toHaveText("Callout on");

  await page.keyboard.press("End");
  await page.keyboard.press("Enter");
  await page.keyboard.type("!!! A shortcut");
  await expect(editable.locator("aside.dev-callout")).toHaveText(["Mind the gap", "A shortcut"]);
  await expectNodes(page, "dev-callout", 2, "comment_body");

  // From the keyboard: Alt+F10 reaches the toolbar, and the button toggles.
  await page.keyboard.press("Alt+F10");
  await page.keyboard.press("End");
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await expect(callout).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(editable.locator("aside.dev-callout")).toHaveCount(1);
  await expect(page.locator(`#${COMMENT} .kotoba-live`)).toHaveText("Callout off");

  // The other editor does not have the extension.
  await page.locator("#notes_editor .kotoba-editable").click();
  await page.keyboard.type("!!! not a callout");
  await expect(page.locator("#notes_editor aside.dev-callout")).toHaveCount(0);
});

test("an extension is cleaned up when its editor goes, and registered again when it comes back", async ({ page }) => {
  await openEditor(page, "/extensions", COMMENT);
  const registrations = () => page.evaluate(() => (window as unknown as { kotobaDevCallouts?: number }).kotobaDevCallouts);
  await expect.poll(registrations).toBe(1);

  await page.getByRole("button", { name: "Toggle the comment editor" }).click();
  await expect(page.locator(`#${COMMENT}`)).toHaveCount(0);
  await expect.poll(registrations).toBe(0);

  await page.getByRole("button", { name: "Toggle the comment editor" }).click();
  await expect(page.locator(`#${COMMENT} .kotoba-editable`)).toBeVisible();
  await expect.poll(registrations).toBe(1);
  await expect(toolbar(page).getByRole("button", { name: "Callout" })).toHaveCount(1);
});

test("an extension that throws or does not load is logged, and the editor mounts with the others", async ({ page }) => {
  const messages = collectConsole(page);
  const editable = await openEditor(page, "/extensions?case=broken", COMMENT);

  await expect.poll(() => messages.some((message) => message.includes("could not load the extension module"))).toBe(true);
  await expect.poll(() => messages.some((message) => message.includes('the extension "broken" could not register'))).toBe(true);

  await editable.click();
  await page.keyboard.type("still works");
  await toolbar(page).getByRole("button", { name: "Callout" }).click();
  await expect(editable.locator("aside.dev-callout")).toHaveText("still works");
});
