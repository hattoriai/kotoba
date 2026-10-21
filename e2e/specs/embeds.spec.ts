// Embeds: live things of the app's own in the document (/embeds, polls
// that the development app renders).

import { expect, test, type Page } from "@playwright/test";
import { openEditor, readDocument, settle } from "./support";

const EDITOR = "embeds-body";
const polls = (page: Page) => page.locator(`#${EDITOR} .kotoba-embed-slot .poll`);

async function open(page: Page, path = "/embeds") {
  const editable = await openEditor(page, path, EDITOR);
  await expect(polls(page)).toHaveCount(1);
  return editable;
}

test("an embed is the app's live content, in the document", async ({ page }) => {
  await open(page);
  const ramen = polls(page).locator("li button").first();
  await expect(ramen).toContainText("4");
  await ramen.click();
  await expect(ramen).toContainText("5");

  // Typing around it keeps the same content: no remount.
  await page.evaluate(() => ((window as any).poll = document.querySelector(".kotoba-embed-slot .poll")));
  await page.getByText("The team decides").click();
  await page.keyboard.press("End");
  await page.keyboard.type(" Quickly.");
  await expect(page.getByText("The team decides, live, in the document: Quickly.")).toBeVisible();
  expect(await page.evaluate(() => (window as any).poll === document.querySelector(".kotoba-embed-slot .poll"))).toBe(true);
});

test("keys in an embed are the embed's", async ({ page }) => {
  await open(page);
  const before = JSON.stringify(await readDocument(page, "doc_body"));
  await polls(page).locator("li button").first().focus();
  await page.keyboard.press("Backspace");
  await page.keyboard.press("Delete");
  await page.keyboard.type("zz");
  await expect(polls(page)).toHaveCount(1);
  expect(JSON.stringify(await readDocument(page, "doc_body"))).toBe(before);
});

test("the toolbar's button opens the app's picker, and an option inserts an embed", async ({ page }) => {
  await open(page);
  const button = page.getByRole("button", { name: "Poll", exact: true });
  await expect(button).toHaveAttribute("aria-haspopup", "dialog");

  await page.getByText("Vote in the poll").click();
  await page.keyboard.press("End");
  await settle(page);
  await button.click();
  const picker = page.getByRole("dialog", { name: "Insert a poll" });
  await expect(picker).toBeVisible();
  await expect(picker.getByRole("button", { name: /A new poll/ })).toBeFocused();

  await page.keyboard.press("Escape");
  await expect(picker).toHaveCount(0);

  await button.click();
  await picker.getByRole("button", { name: /When do we launch/ }).click();
  await expect(picker).toHaveCount(0);
  await expect(polls(page)).toHaveCount(2);
  await expect(polls(page).nth(1)).toContainText("When do we launch?");

  const doc = await readDocument(page, "doc_body");
  const embeds = doc.root.children!.filter((node) => node.type === "embed");
  expect(embeds.map((node) => [node.kind, node.ref, node.title])).toEqual([
    ["poll", "lunch", "Where do we have lunch?"],
    ["poll", "launch", "When do we launch?"],
  ]);
});

test("full screen and back: the same content, over the page", async ({ page }) => {
  await open(page);
  await page.evaluate(() => ((window as any).poll = document.querySelector(".kotoba-embed-slot .poll")));
  await polls(page).getByRole("button", { name: "Full screen" }).click();

  const layer = page.locator("#embeds-body-embeds-full-body");
  await expect(layer.locator(".poll")).toBeVisible();
  expect(await page.evaluate(() => (window as any).poll === document.querySelector("#embeds-body-embeds-full-body .poll"))).toBe(true);

  await page.keyboard.press("Escape");
  await expect(layer.locator(".poll")).toHaveCount(0);
  await expect(polls(page)).toHaveCount(1);
  expect(await page.evaluate(() => (window as any).poll === document.querySelector(".kotoba-embed-slot .poll"))).toBe(true);
});

test("Backspace after an embed deletes it, and undo brings it back, live", async ({ page }) => {
  await open(page);
  await page.getByText("Vote in the poll").click();
  await page.keyboard.press("Home");
  await settle(page);
  await page.keyboard.press("Backspace");
  await expect(polls(page)).toHaveCount(0);
  expect((await readDocument(page, "doc_body")).root.children!.some((node) => node.type === "embed")).toBe(false);

  await page.keyboard.press("ControlOrMeta+z");
  await expect(polls(page)).toHaveCount(1);
  await polls(page).locator("li button").first().click();
  await expect(polls(page).locator("li button").first()).toContainText("5");
});

test("the reading page: no toolbar, and read-only embeds", async ({ page }) => {
  await open(page, "/embeds?read=1");
  await expect(page.locator(`#${EDITOR} .kotoba-toolbar`)).toBeHidden();
  await expect(polls(page).locator("li button").first()).toBeDisabled();
  await expect(polls(page).getByRole("button", { name: "Full screen" })).toBeEnabled();
});
