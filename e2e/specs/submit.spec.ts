import { expect, test } from "@playwright/test";

import { MOD, expectNodes, openEditor, readDocument } from "./support";

test("submit posts the document, and the stored content renders below", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("# Title");
  await page.keyboard.press("Enter");
  await page.keyboard.type("Hello ");
  await page.keyboard.press(`${MOD}+B`);
  await page.keyboard.type("world");
  await page.keyboard.press(`${MOD}+B`);
  await page.keyboard.type(" and @grace");
  await expect(page.getByRole("option")).toHaveCount(1);
  await page.keyboard.press("Enter");
  await page.keyboard.press("Enter");
  await page.keyboard.type("- item");
  await expectNodes(page, "mention", 1);

  const sent = await readDocument(page);
  await page.getByRole("button", { name: "Submit" }).click();

  const stored = page.locator("#stored-content");
  await expect(stored.locator("h1")).toHaveText("Title");
  await expect(stored.locator("strong")).toHaveText("world");
  await expect(stored.locator(".kotoba-mention")).toHaveText("Grace Hopper");
  await expect(stored.locator("ul li")).toHaveText("item");
  await expect(page.locator("#stored-text")).toContainText("Hello world and Grace Hopper");

  const json = JSON.parse((await page.locator("#stored-json").textContent()) ?? "{}");
  expect(json.root).toEqual(sent.root);
});

test("the formdata event puts the current document in the submit, even over a stale input", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Fresh text");
  await expectNodes(page, "text", 1);

  // A patch from the server could reset the hidden input; do it by hand.
  await page.locator("#post_body").evaluate((input) => {
    (input as HTMLInputElement).value = '{"kotoba":1,"lexical":"0.51","root":{"type":"root","children":[]}}';
  });

  await page.getByRole("button", { name: "Submit" }).click();
  await expect(page.locator("#stored-text")).toHaveText("Fresh text");
});

test("the formdata event puts the current document in a phx-change", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Changed text");
  await expectNodes(page, "text", 1);

  await page.locator("#post_body").evaluate((input) => {
    (input as HTMLInputElement).value = "";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });

  await expect(page.locator("#validate-count")).toHaveText("1");
  await expect(page.locator("#validated-text")).toHaveText("Changed text");
});

test("Enter in the editor does not submit the form", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("line");
  await page.keyboard.press("Enter");
  await page.keyboard.type("next");

  await expectNodes(page, "paragraph", 2);
  await expect(page.locator("#stored")).toHaveCount(0);
});
