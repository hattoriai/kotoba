import { expect, test } from "@playwright/test";

import { expectNodes, nodesOfType, openEditor } from "./support";

test.beforeEach(async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
});

test("# and #### make headings, ##### stays text", async ({ page }) => {
  const editable = page.locator("#post_body_editor .kotoba-editable");
  await page.keyboard.type("# Title");
  await page.keyboard.press("Enter");
  await page.keyboard.type("#### Small");
  await page.keyboard.press("Enter");
  await page.keyboard.type("##### Not a heading");

  await expect(editable.locator("h1")).toHaveText("Title");
  await expect(editable.locator("h4")).toHaveText("Small");
  await expect(editable.locator("p").last()).toHaveText("##### Not a heading");
  const headings = await expectNodes(page, "heading", 2);
  expect(headings.map((node) => node.tag)).toEqual(["h1", "h4"]);
});

test("- and 1. make lists, [] a check list", async ({ page }) => {
  const editable = page.locator("#post_body_editor .kotoba-editable");
  await page.keyboard.type("- bullet");
  await page.keyboard.press("Enter");
  await page.keyboard.press("Enter");
  await page.keyboard.type("1. first");
  await page.keyboard.press("Enter");
  await page.keyboard.press("Enter");
  await page.keyboard.type("[] task");

  await expect(editable.locator("ul.kotoba-ul:not(.kotoba-check) li")).toHaveText("bullet");
  await expect(editable.locator("ol.kotoba-ol li")).toHaveText("first");
  await expect(editable.locator("ul.kotoba-check li")).toHaveText("task");
  const lists = await expectNodes(page, "list", 3);
  expect(lists.map((node) => node.listType)).toEqual(["bullet", "number", "check"]);
});

test("> makes a quote", async ({ page }) => {
  const editable = page.locator("#post_body_editor .kotoba-editable");
  await page.keyboard.type("> Quoted");
  await expect(editable.locator("blockquote.kotoba-quote")).toHaveText("Quoted");
  await expectNodes(page, "quote", 1);
});

test("--- makes a horizontal rule", async ({ page }) => {
  const editable = page.locator("#post_body_editor .kotoba-editable");
  await page.keyboard.type("Above");
  await page.keyboard.press("Enter");
  await page.keyboard.type("--- ");
  await page.keyboard.type("Below");

  await expect(editable.locator("hr")).toHaveCount(1);
  await expectNodes(page, "horizontalrule", 1);
  const texts = await nodesOfType(page, "text");
  expect(texts.map((node) => node.text)).toEqual(["Above", "Below"]);
});

test("backticks make inline code and ``` a code block", async ({ page }) => {
  const editable = page.locator("#post_body_editor .kotoba-editable");
  await page.keyboard.type("Run `mix dev` now");
  await expect(editable.locator("p code")).toHaveText("mix dev");
  const texts = await nodesOfType(page, "text");
  expect(texts.find((node) => node.text === "mix dev")?.format).toBe(16);

  await page.keyboard.press("Enter");
  await page.keyboard.type("``` ");
  await page.keyboard.type("IO.puts(1)");
  await expect(editable.locator("code.kotoba-code")).toContainText("IO.puts(1)");
  await expectNodes(page, "code", 1);
});

test("**bold** and *italic* format the text", async ({ page }) => {
  const editable = page.locator("#post_body_editor .kotoba-editable");
  await page.keyboard.type("**strong** and *soft* ");
  await expect(editable.locator("strong")).toHaveText("strong");
  await expect(editable.locator("em")).toHaveText("soft");
});
