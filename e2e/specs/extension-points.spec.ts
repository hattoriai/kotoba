import { expect, test, type Page } from "@playwright/test";

import { MOD, collectConsole, expectNodes, nodesOfType, openEditor, selectBack } from "./support";

// The extension points, with the example extension of /points
// (dev/assets/js/kotoba/nodes/points.js).

const EDITOR = "points_editor";
const INPUT = "points_body";
const dialog = (page: Page) => page.locator(`#${EDITOR}`).getByRole("dialog", { name: "Link" });
const toolbar = (page: Page) => page.locator(`#${EDITOR}`).getByRole("toolbar", { name: "Formatting", exact: true });
const rendered = (page: Page) => page.locator("#points-rendered");

async function linkWords(page: Page, text: string, selected: number): Promise<void> {
  const editable = await openEditor(page, "/points", EDITOR);
  await editable.click();
  await page.keyboard.type(text);
  await selectBack(page, selected);
}

test("an extension gets the editor's Lexical packages, Kotoba's nodes and the inline functions", async ({ page }) => {
  const errors = collectConsole(page);
  await openEditor(page, "/points", EDITOR);

  expect(await page.evaluate(() => (window as unknown as { kotobaDevApi: string[] }).kotobaDevApi)).toEqual([
    "code",
    "inline",
    "lexical",
    "link",
    "list",
    "mark",
    "nodes",
    "richText",
    "selection",
    "table",
    "utils",
    "version",
  ]);
  expect(errors).toEqual([]);
});

test("the link form lists an extension's suggestions for words, and applies the one chosen", async ({ page }) => {
  await linkWords(page, "Read Kotoba", 6);
  await page.keyboard.press(`${MOD}+K`);

  const input = dialog(page).getByRole("combobox", { name: "Link" });
  await expect(input).toBeFocused();
  await expect(input).toHaveAttribute("placeholder", "Paste a link or search");
  await input.fill("kot");

  const options = dialog(page).getByRole("option");
  await expect(options).toHaveText(["Kotoba/docs/kotoba", "Kotoba guides/docs/kotoba-guides"]);
  await expect(input).toHaveAttribute("aria-expanded", "true");
  // Words: the first suggestion is selected, so Enter takes it.
  await expect(options.nth(0)).toHaveAttribute("aria-selected", "true");
  await input.press("ArrowDown");
  await expect(options.nth(1)).toHaveAttribute("aria-selected", "true");
  await expect(input).toHaveAttribute("aria-activedescendant", (await options.nth(1).getAttribute("id"))!);
  await input.press("ArrowDown");
  await expect(options.nth(0)).toHaveAttribute("aria-selected", "true");
  await input.press("Enter");

  await expect(dialog(page)).toBeHidden();
  const [link] = await expectNodes(page, "link", 1, INPUT);
  expect(link?.url).toBe("/pages/5");
  // The server renders the page's path now (the override).
  await expect(rendered(page).locator("a")).toHaveAttribute("href", "/docs/kotoba");
});

test("a click applies a suggestion; a URL has no suggestions; Escape closes the list, then the form", async ({ page }) => {
  await linkWords(page, "Read Issho", 5);
  await page.keyboard.press(`${MOD}+K`);
  const input = dialog(page).getByRole("combobox", { name: "Link" });

  await input.fill("https://hattori.ai");
  await expect(input).toHaveAttribute("aria-expanded", "false");
  await expect(dialog(page).getByRole("option")).toHaveCount(0);

  await input.fill("iss");
  await expect(dialog(page).getByRole("option")).toHaveText(["Issho/docs/issho"]);
  await input.press("Escape");
  await expect(dialog(page).getByRole("option")).toHaveCount(0);
  await expect(dialog(page)).toBeVisible();

  await input.fill("issho");
  await dialog(page).getByRole("option", { name: /Issho/ }).click();
  await expect(dialog(page)).toBeHidden();
  const [link] = await expectNodes(page, "link", 1, INPUT);
  expect(link?.url).toBe("/pages/6");
  await expect(rendered(page).locator("a")).toHaveAttribute("href", "/docs/issho");
});

test("Enter with no suggestion chosen applies the URL typed", async ({ page }) => {
  await linkWords(page, "Read more", 4);
  await page.keyboard.press(`${MOD}+K`);
  const input = dialog(page).getByRole("combobox", { name: "Link" });
  await input.fill("hattori.ai/kotoba");
  await input.press("Enter");

  const [link] = await expectNodes(page, "link", 1, INPUT);
  expect(link?.url).toBe("https://hattori.ai/kotoba");
});

test("an extension can have the link form: Kotoba's does not open, and apply keeps the selection", async ({ page }) => {
  await linkWords(page, "Read the Storehouse guide", 16);
  await page.evaluate(() => ((window as unknown as { kotobaDevOwnLinkForm: boolean }).kotobaDevOwnLinkForm = true));

  await toolbar(page).getByRole("button", { name: "Link" }).click();
  await expect(dialog(page)).toBeHidden();

  type Request = { url: string | null; text: string; apply(url: string | null): boolean };
  const text = await page.evaluate(() => (window as unknown as { kotobaDevLinkRequest: Request }).kotobaDevLinkRequest.text);
  expect(text).toBe("Storehouse guide");

  // A URL that the link schemes refuse is not applied.
  expect(
    await page.evaluate(() => (window as unknown as { kotobaDevLinkRequest: Request }).kotobaDevLinkRequest.apply("javascript:alert(1)")),
  ).toBe(false);
  // The selection moves meanwhile; the link goes on the request's.
  await page.keyboard.press("End");
  expect(
    await page.evaluate(() => (window as unknown as { kotobaDevLinkRequest: Request }).kotobaDevLinkRequest.apply("/pages/7")),
  ).toBe(true);

  const [link] = await expectNodes(page, "link", 1, INPUT);
  expect(link?.url).toBe("/pages/7");
  await expect(page.locator(`#${EDITOR} .kotoba-editable a`)).toHaveText("Storehouse guide");
  await expect(rendered(page).locator("a")).toHaveAttribute("href", "/docs/storehouse");
});

test("an extension keeps its own state on a built-in link, shows it, and the server renders it", async ({ page }) => {
  await linkWords(page, "Visit Hattori", 7);
  await page.keyboard.press(`${MOD}+K`);
  const input = dialog(page).getByRole("combobox", { name: "Link" });
  await input.fill("https://hattori.ai");
  await input.press("Enter");
  // The caret in the link's text.
  await page.locator(`#${EDITOR} .kotoba-editable a`).click();

  const newTab = toolbar(page).getByRole("button", { name: "Open in a new tab" });
  await newTab.click();
  await expect(newTab).toHaveAttribute("aria-pressed", "true");

  await expect.poll(async () => (await nodesOfType(page, "link", INPUT))[0]?.["$"]).toEqual({ target: "_blank" });
  await expect(page.locator(`#${EDITOR} .kotoba-editable a`)).toHaveAttribute("data-target", "_blank");
  await expect(rendered(page).locator("a")).toHaveAttribute("target", "_blank");

  await newTab.click();
  await expect.poll(async () => (await nodesOfType(page, "link", INPUT))[0]?.["$"]).toBeUndefined();
  await expect(page.locator(`#${EDITOR} .kotoba-editable a`)).not.toHaveAttribute("data-target");
  await expect(rendered(page).locator("a")).not.toHaveAttribute("target");
});

test("an extension's mark goes over the selected text and comes off, from the toolbar and the selection menu", async ({ page }) => {
  await linkWords(page, "the butler", 6);

  const spoiler = toolbar(page).getByRole("button", { name: "Spoiler" });
  await spoiler.click();
  await expect(spoiler).toHaveAttribute("aria-pressed", "true");

  const [mark] = await expectNodes(page, "dev-spoiler", 1, INPUT);
  expect(mark?.children?.map((child) => child.text).join("")).toBe("butler");
  await expect(page.locator(`#${EDITOR} .kotoba-editable .dev-spoiler`)).toHaveText("butler");
  await expect(rendered(page).locator(".dev-spoiler")).toHaveText("butler");

  // The selection menu has the extension's control too.
  const menu = page.locator(`#${EDITOR} .kotoba-selection-menu`);
  await expect(menu).toBeVisible();
  const menuSpoiler = menu.getByRole("button", { name: "Spoiler" });
  await expect(menuSpoiler).toHaveAttribute("aria-pressed", "true");
  await menuSpoiler.click();

  await expectNodes(page, "dev-spoiler", 0, INPUT);
  await expect(rendered(page).locator(".dev-spoiler")).toHaveCount(0);
  await expect(rendered(page)).toHaveText("the butler");
});
