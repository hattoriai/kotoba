import { expect, test, type Page } from "@playwright/test";

import { expectNodes, openEditor, pasteText, readDocument, settle } from "./support";

const toolbar = (page: Page, editorId = "post_body_editor") =>
  page.locator(`#${editorId}`).getByRole("toolbar", { name: "Formatting" });
const picker = (page: Page, editorId = "post_body_editor") =>
  toolbar(page, editorId).getByRole("combobox", { name: "Code language" });
const live = (page: Page) => page.locator("#post_body_editor .kotoba-live");

/** The language of the first code block of the hidden input, as it is stored. */
async function language(page: Page, inputId = "post_body"): Promise<unknown> {
  const doc = await readDocument(page, inputId);
  return doc.root.children?.find((node) => node.type === "code")?.language;
}

test("the picker shows in a code block, with its language, and keeps an alias", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Intro");
  await expect(picker(page)).toBeHidden();

  await page.keyboard.press("Enter");
  await page.keyboard.type("```js ");
  await page.keyboard.type("const answer = 42;");
  await settle(page);

  await expect(picker(page)).toBeVisible();
  // "js" is an alias: the picker shows JavaScript, and the block keeps "js".
  await expect(picker(page)).toHaveValue("javascript");
  await expect.poll(() => language(page)).toBe("js");

  const labels = await picker(page).locator("option").allTextContents();
  expect(labels[0]).toBe("Plain text");
  expect(labels.length).toBeGreaterThanOrEqual(21);
  expect(labels).toEqual(expect.arrayContaining(["Elixir", "Erlang", "YAML", "Dockerfile", "Ruby", "PHP", "TOML"]));

  await editable.locator("p").first().click();
  await settle(page);
  await expect(picker(page)).toBeHidden();
});

test("picking a language sets it, highlights the block and says so", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("``` ");
  await page.keyboard.type("def greet(name): return name");
  await settle(page);

  // A block with no language is plain text.
  await expect(picker(page)).toHaveValue("plain");
  await expect(editable.locator("code [class*='kotoba-token']")).toHaveCount(0);

  await picker(page).selectOption("python");
  await expect.poll(() => language(page)).toBe("python");
  await expect(editable.locator("code.kotoba-code")).toHaveAttribute("data-language", "python");
  await expect(editable.locator("code .kotoba-token-keyword").first()).toHaveText("def");
  await expect(live(page)).toHaveText("Code language Python");

  // Pasted code is highlighted in the block's language.
  await editable.locator("code").click();
  await page.keyboard.press("End");
  await page.keyboard.press("Enter");
  await pasteText(page, editable, "import os");
  await expect(editable.locator("code .kotoba-token-keyword")).toHaveText(["def", "return", "import"]);

  await picker(page).selectOption("plain");
  await expect.poll(() => language(page)).toBeUndefined();
  await expect(editable.locator("code [class*='kotoba-token']")).toHaveCount(0);
});

test("from the keyboard, Up and Down choose a language and the focus stays on the picker", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("```elixir ");
  await page.keyboard.type("defmodule A do end");
  await settle(page);

  await page.keyboard.press("Alt+F10");
  await page.keyboard.press("End");
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await expect(picker(page)).toBeFocused();
  await expect(picker(page)).toHaveValue("elixir");

  await page.keyboard.press("ArrowDown");
  await expect.poll(() => language(page)).toBe("erlang");
  await expect(picker(page)).toBeFocused();
  await expect(live(page)).toHaveText("Code language Erlang");

  // Left and Right move along the toolbar.
  await page.keyboard.press("ArrowRight");
  await expect(toolbar(page).getByRole("button", { name: "Undo" })).toBeFocused();
});

test("an editor offers the languages of its code_languages, and keeps the language of a loaded block", async ({
  page,
}) => {
  await openEditor(page, "/two", "a_editor");
  const second = page.locator("#b_editor .kotoba-editable");
  await page.getByRole("button", { name: "Load the second editor" }).click();
  await expect(second.locator("h2")).toHaveText("Second");

  // The sample's code block is in "ex", an alias of Elixir.
  await second.locator("code").click();
  await settle(page);
  const secondPicker = picker(page, "b_editor");
  await expect(secondPicker).toBeVisible();
  await expect(secondPicker.locator("option")).toHaveText(["Plain text", "Elixir", "Erlang", "SQL"]);
  await expect(secondPicker).toHaveValue("elixir");
  await expect(second.locator("code .kotoba-token-keyword").first()).toHaveText("defmodule");
  await expect.poll(() => language(page, "b_body")).toBe("ex");
  await expectNodes(page, "code", 1, "b_body");
});

test("the language is sent, stored and rendered", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("``` ");
  await page.keyboard.type("SELECT 1;");
  await settle(page);
  await picker(page).selectOption("sql");
  await expect.poll(() => language(page)).toBe("sql");

  await page.getByRole("button", { name: "Submit" }).click();
  await expect(page.locator("#stored-content pre code.language-sql")).toHaveText("SELECT 1;");
  const json = JSON.parse((await page.locator("#stored-json").textContent()) ?? "{}");
  expect(json.root.children[0].language).toBe("sql");
});
