import { expect, test, type Page } from "@playwright/test";

import { MOD, expectNodes, nodesOfType, openEditor, pasteText, selectBack } from "./support";

const dialog = (page: Page) => page.getByRole("dialog", { name: "Link" });
const live = (page: Page) => page.locator("#post_body_editor .kotoba-live");

test("a URL pasted over a selection makes a link", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Visit Kotoba");
  await selectBack(page, 6);
  await pasteText(page, editable, "https://example.com/kotoba");

  await expect(editable.locator("a")).toHaveText("Kotoba");
  const [link] = await expectNodes(page, "link", 1);
  expect(link?.url).toBe("https://example.com/kotoba");
});

test("a pasted URL with no selection becomes an automatic link", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("See ");
  await pasteText(page, editable, "https://hexdocs.pm");
  await page.keyboard.type(" today");

  const [link] = await expectNodes(page, "autolink", 1);
  expect(link?.url).toBe("https://hexdocs.pm");
});

test("Cmd/Ctrl+K opens the link form under the selection and keeps the selection", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Read the docs");
  await selectBack(page, 4);
  const selection = await page.evaluate(() => {
    const rect = window.getSelection()!.getRangeAt(0).getBoundingClientRect();
    return { left: rect.left, bottom: rect.bottom };
  });

  await page.keyboard.press(`${MOD}+K`);
  await expect(dialog(page)).toBeVisible();
  const input = dialog(page).getByLabel("URL");
  await expect(input).toBeFocused();

  // The form is under the selected text.
  const box = (await dialog(page).boundingBox())!;
  expect(box.y).toBeGreaterThanOrEqual(selection.bottom);
  expect(Math.abs(box.x - selection.left)).toBeLessThan(2);

  // A relative link is kept.
  await input.fill("/docs#top");
  await input.press("Enter");

  await expect(dialog(page)).toBeHidden();
  await expect(editable).toBeFocused();
  await expect(editable.locator("a")).toHaveText("docs");
  await expect(live(page)).toHaveText("Link applied");
  const [link] = await expectNodes(page, "link", 1);
  expect(link?.url).toBe("/docs#top");
  // Enter in the form did not submit the page's form.
  await expect(page.locator("#stored")).toHaveCount(0);
});

test("a bare domain gets https:// and an email gets mailto:", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("site mail");
  await selectBack(page, 4);
  await page.keyboard.press(`${MOD}+K`);
  await dialog(page).getByLabel("URL").fill("ada@example.com");
  await page.keyboard.press("Enter");

  await page.keyboard.press("Home");
  await page.keyboard.press("Shift+ArrowRight");
  await page.keyboard.press("Shift+ArrowRight");
  await page.keyboard.press("Shift+ArrowRight");
  await page.keyboard.press("Shift+ArrowRight");
  await page.getByRole("button", { name: "Link" }).click();
  await dialog(page).getByLabel("URL").fill("example.com");
  await dialog(page).getByRole("button", { name: "Apply" }).click();

  const links = await expectNodes(page, "link", 2);
  expect(links.map((node) => node.url)).toEqual(["https://example.com", "mailto:ada@example.com"]);
});

test("javascript: is refused, and the form stays open", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("click me");
  await selectBack(page, 2);
  await page.keyboard.press(`${MOD}+K`);

  const input = dialog(page).getByLabel("URL");
  await input.fill("javascript:alert(1)");
  await input.press("Enter");

  await expect(live(page)).toContainText("Enter a relative URL or a URL that starts with");
  await expect(dialog(page)).toBeVisible();
  await expect(input).toBeFocused();
  expect(await nodesOfType(page, "link")).toEqual([]);

  // Escape closes the form and gives the focus back to the editor.
  await input.press("Escape");
  await expect(dialog(page)).toBeHidden();
  await expect(editable).toBeFocused();
  await expect(editable.locator("a")).toHaveCount(0);
});

test("a markdown link to javascript: stays text", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("[x](javascript:alert(1)) and [ok](https://example.com) ");

  await expect(editable.locator("a")).toHaveCount(1);
  const links = await expectNodes(page, "link", 1);
  expect(links[0]?.url).toBe("https://example.com");
});

test("data-link-schemes sets the allowed schemes", async ({ page }) => {
  const editable = await openEditor(page);
  // The development server allows tel: as well (config :kotoba, allowed_link_schemes:).
  await expect(page.locator("#post_body_editor")).toHaveAttribute("data-link-schemes", "http,https,mailto,tel");

  await editable.click();
  await page.keyboard.type("call ftp");
  await selectBack(page, 3);
  await page.keyboard.press(`${MOD}+K`);
  await dialog(page).getByLabel("URL").fill("ftp://example.com");
  await page.keyboard.press("Enter");
  await expect(live(page)).toContainText("http, https, mailto, tel");
  await page.keyboard.press("Escape");

  await page.keyboard.press("Home");
  for (let i = 0; i < 4; i += 1) await page.keyboard.press("Shift+ArrowRight");
  await page.keyboard.press(`${MOD}+K`);
  await dialog(page).getByLabel("URL").fill("tel:+15550100");
  await page.keyboard.press("Enter");

  const links = await expectNodes(page, "link", 1);
  expect(links[0]?.url).toBe("tel:+15550100");
  await expect(editable.locator("a")).toHaveText("call");
});

test("the Remove button removes a link", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("linked");
  await selectBack(page, 6);
  await page.keyboard.press(`${MOD}+K`);
  await dialog(page).getByLabel("URL").fill("https://example.com");
  await page.keyboard.press("Enter");
  await expectNodes(page, "link", 1);

  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press(`${MOD}+K`);
  await expect(dialog(page).getByLabel("URL")).toHaveValue("https://example.com");
  await dialog(page).getByRole("button", { name: "Remove" }).click();

  await expectNodes(page, "link", 0);
  await expect(editable).toHaveText("linked");
});
