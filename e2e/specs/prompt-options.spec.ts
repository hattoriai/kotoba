import { expect, test, type Page } from "@playwright/test";

import { expectNodes, nodesOfType, openEditor } from "./support";

const menu = (page: Page) => page.locator("#post_body_editor .kotoba-menu");
const status = (page: Page) => menu(page).locator(".kotoba-menu-status");
const live = (page: Page) => page.locator("#post_body_editor .kotoba-live");

test("a query with spaces finds a full name, and two spaces end it", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Thanks @ada lo");

  const options = page.getByRole("listbox", { name: "people suggestions" }).getByRole("option");
  await expect(options).toHaveCount(1);
  await expect(options.first()).toContainText("Ada Lovelace");

  // A space at the end searches the words before it.
  await page.keyboard.press("Backspace");
  await page.keyboard.press("Backspace");
  await expect(options).toHaveCount(1);
  await page.keyboard.type(" ");
  await expect(menu(page)).toBeHidden();

  await page.keyboard.press("Backspace");
  await page.keyboard.type("lovelace");
  await expect(options).toHaveCount(1);
  await page.keyboard.press("Enter");

  const [mention] = await expectNodes(page, "mention", 1);
  expect(mention).toMatchObject({ kind: "people", id: "1", label: "Ada Lovelace" });
  await expect(live(page)).toHaveText("Inserted Ada Lovelace");
});

test("a local prompt filters its items in the page and inserts text", async ({ page }) => {
  const requests: string[] = [];
  page.on("websocket", (socket) =>
    socket.on("framesent", (frame) => {
      if (typeof frame.payload === "string" && frame.payload.includes("kotoba:prompt")) requests.push(frame.payload);
    }),
  );
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Shipped :ro");

  const listbox = page.getByRole("listbox", { name: "Emoji" });
  await expect(listbox.getByRole("option")).toHaveCount(1);
  await expect(listbox.getByRole("option").first()).toContainText("rocket");
  await expect(listbox.getByRole("option").first()).toContainText("🚀");
  await expect(live(page)).toHaveText("1 result");

  // Each word of the query starts a word of the label.
  await page.keyboard.press("Backspace");
  await page.keyboard.press("Backspace");
  await page.keyboard.type("thu");
  await expect(listbox.getByRole("option")).toHaveCount(1);
  await expect(listbox.getByRole("option").first()).toContainText("thumbs up");
  await page.keyboard.press("Enter");

  await expect(editable).toContainText("Shipped 👍 ");
  await page.keyboard.type("today");
  await expect(editable).toContainText("Shipped 👍 today");
  expect(await nodesOfType(page, "mention")).toEqual([]);
  expect(requests).toEqual([]);
});

test("an async prompt inserts a node of the app", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Label +ur");

  const options = page.getByRole("listbox", { name: "Tags" }).getByRole("option");
  await expect(options).toHaveCount(1);
  await expect(options.first()).toContainText("urgent");
  await page.keyboard.press("Tab");

  const [tag] = await expectNodes(page, "dev-tag", 1);
  expect(tag).toEqual({ type: "dev-tag", version: 1, label: "urgent" });
  await expect(editable.locator(".dev-tag")).toHaveText("urgent");
  await page.keyboard.type("now");
  await expect(editable).toContainText("urgent now");

  await page.getByRole("button", { name: "Submit" }).click();
  await expect(page.locator("#stored-content span.dev-tag")).toHaveText("urgent");
});

test("a slow async search shows Searching, and editing goes on meanwhile", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();

  // The prompt needs one character before it searches.
  await page.keyboard.type("~");
  await expect(status(page)).toHaveText("Keep typing to search");

  await page.keyboard.type("gr");
  await expect(status(page)).toHaveText("Searching…");
  const options = page.getByRole("listbox", { name: "slow suggestions" }).getByRole("option");
  await expect(options).toHaveCount(1, { timeout: 5000 });
  await expect(options.first()).toContainText("Grace Hopper");

  // The first answer is kept: back to it, no second wait.
  await page.keyboard.type("x");
  await expect(status(page)).toHaveText("Searching…");
  await page.keyboard.press("Backspace");
  await expect(options).toHaveCount(1);
  await expect(status(page)).toBeHidden();

  await page.keyboard.press("Escape");
  await expect(menu(page)).toBeHidden();
  await page.keyboard.type(" and more");
  await expect(editable).toContainText("~gr and more");
});
