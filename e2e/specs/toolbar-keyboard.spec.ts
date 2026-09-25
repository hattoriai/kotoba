import { expect, test, type Page } from "@playwright/test";

import { expectNodes, nodesOfType, openEditor, selectBack, settle } from "./support";

const toolbar = (page: Page) => page.getByRole("toolbar", { name: "Formatting" });

test("the toolbar has one tab stop, and the arrows, Home and End move in it", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await settle(page);
  await page.keyboard.press("Shift+Tab");

  const bold = toolbar(page).getByRole("button", { name: "Bold", exact: true });
  await expect(bold).toBeFocused();
  await expect(toolbar(page).locator("button[tabindex='0']")).toHaveCount(1);

  await page.keyboard.press("ArrowRight");
  const italic = toolbar(page).getByRole("button", { name: "Italic" });
  await expect(italic).toBeFocused();
  await expect(italic).toHaveAttribute("tabindex", "0");
  await expect(bold).toHaveAttribute("tabindex", "-1");

  await page.keyboard.press("End");
  await expect(toolbar(page).getByRole("button", { name: "Redo" })).toBeFocused();
  await page.keyboard.press("ArrowRight");
  await expect(bold).toBeFocused();
  await page.keyboard.press("ArrowLeft");
  await expect(toolbar(page).getByRole("button", { name: "Redo" })).toBeFocused();
  await page.keyboard.press("Home");
  await expect(bold).toBeFocused();

  // Tab leaves the toolbar for the editor; Shift+Tab comes back to the last button.
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("Tab");
  await expect(editable).toBeFocused();
  await settle(page);
  await page.keyboard.press("Shift+Tab");
  await expect(italic).toBeFocused();
});

test("a toolbar button from the keyboard formats the kept selection", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("keep this word");
  await selectBack(page, 4);
  await settle(page);
  await page.keyboard.press("Shift+Tab");

  const bold = toolbar(page).getByRole("button", { name: "Bold", exact: true });
  await expect(bold).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(bold).toHaveAttribute("aria-pressed", "true");

  // The focus goes back to the editor, with the selection.
  await expect(editable).toBeFocused();
  expect(await page.evaluate(() => window.getSelection()?.toString())).toBe("word");

  // The toolbar keeps its tab stop on the last button.
  await settle(page);
  await page.keyboard.press("Shift+Tab");
  await expect(bold).toBeFocused();
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press(" ");
  await expect(toolbar(page).getByRole("button", { name: "Italic" })).toHaveAttribute("aria-pressed", "true");

  const texts = await nodesOfType(page, "text");
  expect(texts.map((node) => [node.text, node.format])).toEqual([
    ["keep this ", 0],
    ["word", 3],
  ]);
  await expect(page.locator("#post_body_editor .kotoba-live")).toHaveText("Italic on");
});

test("a toolbar command uses the selection that the page shows, before Lexical reads it", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("select the last word");
  await expectNodes(page, "text", 1);

  // In one task: select "word" in the DOM, then press Bold. Lexical has not
  // had its selectionchange yet.
  await editable.evaluate((element) => {
    const text = element.querySelector("[data-lexical-text]")!.firstChild!;
    const length = text.textContent!.length;
    window.getSelection()!.setBaseAndExtent(text, length - 4, text, length);
    (document.querySelector("#post_body_editor [data-kotoba-command=bold]") as HTMLButtonElement).click();
  });

  await expect(editable.locator("strong")).toHaveText("word");
  const texts = await nodesOfType(page, "text");
  expect(texts.map((node) => [node.text, node.format])).toEqual([
    ["select the last ", 0],
    ["word", 1],
  ]);
});

test("a block button from the keyboard changes the block of the selection", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("A heading");
  await settle(page);
  await page.keyboard.press("Shift+Tab");
  for (let i = 0; i < 6; i += 1) await page.keyboard.press("ArrowRight");

  const h2 = toolbar(page).getByRole("button", { name: "Heading 2" });
  await expect(h2).toBeFocused();
  await page.keyboard.press("Enter");

  await expect(editable.locator("h2")).toHaveText("A heading");
  await expect(h2).toHaveAttribute("aria-pressed", "true");
});

test("the link button from the keyboard opens the form for the kept selection", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("go to Kotoba");
  await selectBack(page, 6);
  await settle(page);
  await page.keyboard.press("Shift+Tab");
  for (let i = 0; i < 4; i += 1) await page.keyboard.press("ArrowRight");
  await expect(toolbar(page).getByRole("button", { name: "Link" })).toBeFocused();
  await page.keyboard.press("Enter");

  const input = page.getByRole("dialog", { name: "Link" }).getByLabel("URL");
  await expect(input).toBeFocused();
  await page.keyboard.type("https://example.com");
  await page.keyboard.press("Enter");

  await expect(editable.locator("a")).toHaveText("Kotoba");
  const [link] = await expectNodes(page, "link", 1);
  expect(link?.url).toBe("https://example.com");
  await expect(toolbar(page).getByRole("button", { name: "Link" })).toHaveAttribute("aria-pressed", "true");
});

test("undo from the toolbar by keyboard", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("to undo");
  await settle(page);
  await page.keyboard.press("Shift+Tab");
  await page.keyboard.press("End");
  await page.keyboard.press("ArrowLeft");

  const undo = toolbar(page).getByRole("button", { name: "Undo" });
  await expect(undo).toBeFocused();
  await expect(undo).toHaveAttribute("aria-disabled", "false");
  await page.keyboard.press("Enter");
  // Lexical keeps the first typed character as its own history step.
  await expect(editable).not.toHaveText("to undo");

  // Back in the toolbar, on Undo; Redo is next to it.
  await settle(page);
  await page.keyboard.press("Shift+Tab");
  await expect(undo).toBeFocused();
  await page.keyboard.press("ArrowRight");
  const redo = toolbar(page).getByRole("button", { name: "Redo" });
  await expect(redo).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(editable).toHaveText("to undo");
  await expectNodes(page, "paragraph", 1);
});

test("a disabled toolbar button does nothing", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await settle(page);
  await page.keyboard.press("Shift+Tab");
  await page.keyboard.press("End");
  const redo = toolbar(page).getByRole("button", { name: "Redo" });
  await expect(redo).toHaveAttribute("aria-disabled", "true");
  await page.keyboard.press("Enter");

  await expect(redo).toBeFocused();
  await expect(editable).toHaveText("");
});
