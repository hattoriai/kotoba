import { expect, test } from "@playwright/test";

import { expectNodes, nodes, openEditor, readDocument } from "./support";

test("a code block highlights Elixir", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("```elixir ");
  await page.keyboard.type("defmodule Hello do");

  const code = editable.locator("code.kotoba-code");
  await expect(code).toHaveAttribute("data-language", "elixir");
  await expect(code.locator(".kotoba-token-keyword").first()).toHaveText("defmodule");
  await expect(code.locator(".kotoba-token-function, .kotoba-token-variable").first()).toBeVisible();

  const [block] = await expectNodes(page, "code", 1);
  expect(block?.language).toBe("elixir");
});

test("the code block button makes a code block", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("const answer = 42");
  await page.getByRole("button", { name: "Code block" }).click();

  await expect(editable.locator("code.kotoba-code")).toContainText("const answer = 42");
  await expect(page.getByRole("button", { name: "Code block" })).toHaveAttribute("aria-pressed", "true");
  await expectNodes(page, "code", 1);
});

test("Tab in a code block inserts a tab and keeps the focus", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("``` ");
  await page.keyboard.type("if x");
  await page.keyboard.press("Enter");
  await page.keyboard.press("Tab");
  await page.keyboard.type("y");

  await expect(editable).toBeFocused();
  const doc = await readDocument(page);
  const code = nodes(doc.root).find((node) => node.type === "code");
  expect(code?.children?.map((node) => node.type)).toContain("tab");
});

test("Enter on two empty lines at the end leaves the code block", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("``` ");
  await page.keyboard.type("one");
  await page.keyboard.press("Enter");
  await page.keyboard.type("two");
  await expect(editable.locator("code.kotoba-code")).toContainText("two");

  await page.keyboard.press("Enter");
  await page.keyboard.press("Enter");
  await page.keyboard.press("Enter");
  await page.keyboard.type("after");

  await expect(editable.locator("p")).toHaveText("after");
  await expectNodes(page, "code", 1);
});

test("Escape then Tab leaves a code block, so the block is no keyboard trap", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("``` ");
  await page.keyboard.type("code");
  await page.keyboard.press("Escape");
  await expect(editable).not.toBeFocused();
  await page.keyboard.press("Tab");
  await expect(editable).not.toBeFocused();

  const doc = await readDocument(page);
  expect(nodes(doc.root).map((node) => node.type)).not.toContain("tab");
});
