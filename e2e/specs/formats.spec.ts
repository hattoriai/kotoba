import { expect, test, type Page } from "@playwright/test";

import { MOD, expectNodes, nodesOfType, openEditor, selectBack, settle } from "./support";

const UNDERLINE = 8;
const SUBSCRIPT = 32;
const SUPERSCRIPT = 64;
const HIGHLIGHT = 128;

const FORMATS = "formats_editor";
const toolbar = (page: Page, editorId: string) =>
  page.locator(`#${editorId}`).getByRole("toolbar", { name: "Formatting" });

async function formats(page: Page, inputId: string): Promise<[string, number][]> {
  return (await nodesOfType(page, "text", inputId)).map((node) => [String(node.text ?? ""), Number(node.format ?? 0)]);
}

test("the default toolbar has underline and highlight, not subscript and superscript", async ({ page }) => {
  await openEditor(page);
  const buttons = toolbar(page, "post_body_editor");

  await expect(buttons.getByRole("button", { name: "Underline" })).toBeVisible();
  await expect(buttons.getByRole("button", { name: "Highlight" })).toBeVisible();
  await expect(buttons.getByRole("button", { name: "Subscript" })).toHaveCount(0);
  await expect(buttons.getByRole("button", { name: "Superscript" })).toHaveCount(0);
});

test("the buttons of an app's toolbar toggle the formats", async ({ page }) => {
  const editable = await openEditor(page, "/extensions", FORMATS);
  const buttons = toolbar(page, FORMATS);
  // Inline code is not a feature of this editor: its button is hidden.
  await expect(buttons.locator("[data-kotoba-command=code]")).toBeHidden();

  await editable.click();
  await page.keyboard.type("H2O and x2");
  await selectBack(page, 1);
  await settle(page);

  const superscript = buttons.getByRole("button", { name: "Superscript" });
  const subscript = buttons.getByRole("button", { name: "Subscript" });
  await superscript.click();
  await expect(superscript).toHaveAttribute("aria-pressed", "true");
  await expect(editable.locator("sup")).toHaveText("2");

  // Subscript and superscript exclude each other.
  await subscript.click();
  await expect(subscript).toHaveAttribute("aria-pressed", "true");
  await expect(superscript).toHaveAttribute("aria-pressed", "false");
  await expect(page.locator(`#${FORMATS} .kotoba-live`)).toHaveText("Subscript on");

  await page.keyboard.press("End");
  await page.keyboard.press("ArrowLeft");
  await selectBack(page, 1);
  await settle(page);
  await buttons.getByRole("button", { name: "Underline" }).click();
  await buttons.getByRole("button", { name: "Highlight" }).click();
  await expect(editable.locator(".kotoba-highlight")).toHaveText("x");
  await expect(editable.locator(".kotoba-underline")).toHaveText("x");

  expect(await formats(page, "formats_body")).toEqual([
    ["H2O and ", 0],
    ["x", UNDERLINE | HIGHLIGHT],
    ["2", SUBSCRIPT],
  ]);
});

test("the keyboard shortcuts of the formats", async ({ page }) => {
  const editable = await openEditor(page, "/extensions", FORMATS);
  await editable.click();

  await page.keyboard.press(`${MOD}+U`);
  await page.keyboard.type("u");
  await page.keyboard.press(`${MOD}+U`);
  await page.keyboard.press(`${MOD}+Shift+H`);
  await page.keyboard.type("h");
  await page.keyboard.press(`${MOD}+Shift+H`);
  await page.keyboard.press(`${MOD}+Comma`);
  await page.keyboard.type("b");
  await page.keyboard.press(`${MOD}+Period`);
  await page.keyboard.type("p");

  await expectNodes(page, "text", 4, "formats_body");
  expect(await formats(page, "formats_body")).toEqual([
    ["u", UNDERLINE],
    ["h", HIGHLIGHT],
    ["b", SUBSCRIPT],
    ["p", SUPERSCRIPT],
  ]);
});

test("in an editor without them, the shortcuts do nothing and pasted formats are dropped", async ({ page }) => {
  const editable = await openEditor(page, "/extensions", "comment_editor");
  await editable.click();

  await page.keyboard.press(`${MOD}+U`);
  await page.keyboard.press(`${MOD}+Shift+H`);
  await page.keyboard.press(`${MOD}+Period`);
  await page.keyboard.type("plain ==not highlighted== ");
  await settle(page);

  await editable.evaluate((element) => {
    const data = new DataTransfer();
    data.setData("text/html", "<p><u>u</u> <mark>m</mark> <sub>b</sub> <sup>p</sup> <b>bold</b></p>");
    data.setData("text/plain", "u m b p bold");
    element.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
  });

  await expect.poll(async () => (await formats(page, "comment_body")).map(([text]) => text).join("")).toContain("bold");
  const texts = await formats(page, "comment_body");
  expect(texts.map(([text]) => text).join("")).toBe("plain ==not highlighted== u m b p bold");
  expect(texts.filter(([, format]) => format !== 0)).toEqual([["bold", 1]]);
});
