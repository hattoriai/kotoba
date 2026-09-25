import { expect, type Page, test } from "@playwright/test";

import { openEditor } from "./support";

// The Sumi theme (kotoba-sumi.css, `?theme=sumi` on the dev page) follows
// the page's theme as Sumi does: data-theme first, then prefers-color-scheme.

async function editorColours(page: Page): Promise<{ background: string; text: string }> {
  return page.locator("#post_body_editor").evaluate((element) => {
    const style = getComputedStyle(element.closest(".kotoba") ?? element);
    return { background: style.backgroundColor, text: style.color };
  });
}

// The lightness of a computed colour, 0 to 1, from the canvas: the browser
// converts oklch() and color-mix() values to sRGB there.
async function lightness(page: Page, colour: string): Promise<number> {
  return page.evaluate((value) => {
    const context = document.createElement("canvas").getContext("2d")!;
    context.fillStyle = value;
    context.fillRect(0, 0, 1, 1);
    const [r, g, b] = context.getImageData(0, 0, 1, 1).data;
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  }, colour);
}

async function setTheme(page: Page, theme: "dark" | "light" | null): Promise<void> {
  await page.evaluate((value) => {
    if (value) document.documentElement.dataset.theme = value;
    else delete document.documentElement.dataset.theme;
  }, theme);
}

test("the dev page loads the Sumi theme with ?theme=sumi", async ({ page }) => {
  await openEditor(page, "/?theme=sumi");
  await expect(page.locator('link[href="/assets/kotoba-sumi.css"]')).toHaveCount(1);
  const font = await page.locator("#post_body_editor .kotoba-editable").evaluate((e) => getComputedStyle(e).fontFamily);
  expect(font).toContain("Outfit");
});

test("the Sumi theme follows prefers-color-scheme", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "light" });
  await openEditor(page, "/?theme=sumi");
  const light = await editorColours(page);

  await page.emulateMedia({ colorScheme: "dark" });
  await expect.poll(async () => (await editorColours(page)).background).not.toBe(light.background);
  const dark = await editorColours(page);

  expect(await lightness(page, light.background)).toBeGreaterThan(0.8);
  expect(await lightness(page, dark.background)).toBeLessThan(0.2);
  expect(await lightness(page, dark.text)).toBeGreaterThan(0.8);
});

test("data-theme wins over prefers-color-scheme", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await openEditor(page, "/?theme=sumi");

  await setTheme(page, "light");
  const light = await editorColours(page);
  expect(await lightness(page, light.background)).toBeGreaterThan(0.8);

  await page.emulateMedia({ colorScheme: "light" });
  await setTheme(page, "dark");
  const dark = await editorColours(page);
  expect(dark.background).not.toBe(light.background);
  expect(await lightness(page, dark.background)).toBeLessThan(0.2);
});

test("the Sumi tokens of the page win over the built-in palette, per theme", async ({ page }) => {
  await openEditor(page, "/?theme=sumi");
  // The theme colours as the Sumi daisyUI themes set them.
  await page.addStyleTag({
    content: `
      :root, [data-theme="dark"] { --color-base-100: rgb(10, 20, 30); --color-base-content: rgb(240, 230, 220); }
      [data-theme="light"] { --color-base-100: rgb(250, 245, 235); --color-base-content: rgb(20, 20, 25); }
    `,
  });

  await setTheme(page, "dark");
  expect(await editorColours(page)).toEqual({ background: "rgb(10, 20, 30)", text: "rgb(240, 230, 220)" });

  await setTheme(page, "light");
  expect(await editorColours(page)).toEqual({ background: "rgb(250, 245, 235)", text: "rgb(20, 20, 25)" });
});

test("without the Sumi theme, the editor keeps the default colours", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await openEditor(page);
  await expect(page.locator('link[href="/assets/kotoba-sumi.css"]')).toHaveCount(0);
  expect((await editorColours(page)).background).toBe("rgb(255, 255, 255)");
});
