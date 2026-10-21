import { expect, test, type Page } from "@playwright/test";
import { openEditor } from "./support";

// The page as a live space: a person's pointer over any part of the page, on the same element of
// everyone's own page whatever its size, and their clicks.
async function open(page: Page, notebook: string, name: string): Promise<void> {
  await openEditor(page, `/collab/notebook?document=${notebook}&name=${name}`, "notebook_one");
  await expect(page.locator("#notebook-people li")).not.toHaveCount(0);
}

const pointer = (page: Page, key: string) => page.locator(`.issho-pointer[data-key="${key}"]`);

async function center(page: Page, selector: string): Promise<{ x: number; y: number }> {
  const box = await page.locator(selector).boundingBox();
  if (!box) throw new Error(`no box for ${selector}`);
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

test("a person's pointer is on the same element of the other's page, and their click rings", async ({ page, browser }) => {
  const notebook = `notebook:${crypto.randomUUID()}`;
  await page.setViewportSize({ width: 1200, height: 900 });
  await open(page, notebook, "Ada");

  const context = await browser.newContext({ viewport: { width: 700, height: 900 } });
  const other = await context.newPage();
  await open(other, notebook, "Grace");

  // Ada points at the middle of the plain paragraph, whose place differs on Grace's narrower page.
  const at = await center(page, "#notebook-note");
  await page.mouse.move(at.x, at.y);

  const theirs = await center(other, "#notebook-note");
  await expect(pointer(other, "Ada")).toBeVisible();
  await expect(pointer(other, "Ada")).toContainText("Ada");
  await expect.poll(async () => {
    const box = await pointer(other, "Ada").boundingBox();
    return box ? Math.abs(box.x - theirs.x) < 4 && Math.abs(box.y - theirs.y) < 4 : false;
  }).toBe(true);
  // No one sees their own pointer.
  await expect(pointer(page, "Ada")).toHaveCount(0);

  await page.mouse.down();
  await page.mouse.up();
  await expect(pointer(other, "Ada").locator(".issho-pointer-click")).toHaveCount(1);

  // Over what is private, nothing is shared.
  const secret = await center(page, "#notebook-secret");
  await page.mouse.move(secret.x, secret.y);
  await expect(pointer(other, "Ada")).toHaveCount(0);
  await context.close();
});

// Where a word is on a page: the box of its characters.
async function word(page: Page, text: string): Promise<{ left: number; right: number; top: number; bottom: number } | null> {
  return page.evaluate((text) => {
    const root = document.querySelector("#notebook_one .kotoba-editable")!;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const at = node.textContent!.indexOf(text);
      if (at < 0) continue;
      const range = document.createRange();
      range.setStart(node, at);
      range.setEnd(node, at + text.length);
      const { left, right, top, bottom } = range.getBoundingClientRect();
      return { left, right, top, bottom };
    }
    return null;
  }, text);
}

test("a pointer over the text is on the same word of the other's page, however it wraps there", async ({ page, browser }) => {
  const notebook = `notebook:${crypto.randomUUID()}`;
  await page.setViewportSize({ width: 1200, height: 900 });
  await open(page, notebook, "Ada");
  const context = await browser.newContext({ viewport: { width: 600, height: 900 } });
  const other = await context.newPage();
  await open(other, notebook, "Grace");

  // A paragraph that wraps in other places on Grace's narrower page.
  await page.locator("#notebook_one .kotoba-editable").click();
  await page.keyboard.type("Every blade has a smith, and every smith a forge. ".repeat(4) + "ZEBRA ends it.");
  await expect(other.locator("#notebook_one .kotoba-editable")).toContainText("ZEBRA");

  const mine = (await word(page, "ZEBRA"))!;
  await page.mouse.move((mine.left + mine.right) / 2, (mine.top + mine.bottom) / 2);

  await expect(pointer(other, "Ada")).toBeVisible();
  await expect.poll(async () => {
    const box = await pointer(other, "Ada").boundingBox();
    const theirs = await word(other, "ZEBRA");
    if (!box || !theirs) return false;
    return box.x >= theirs.left - 2 && box.x <= theirs.right + 2 && box.y >= theirs.top - 2 && box.y <= theirs.bottom + 4;
  }).toBe(true);
  await context.close();
});

test("a pointer beyond the viewport is a marker at its edge that goes to it", async ({ page, browser }) => {
  const notebook = `notebook:${crypto.randomUUID()}`;
  await page.setViewportSize({ width: 900, height: 900 });
  await open(page, notebook, "Ada");

  const context = await browser.newContext({ viewport: { width: 900, height: 300 } });
  const other = await context.newPage();
  await open(other, notebook, "Grace");

  const at = await center(page, "#notebook-note");
  await page.mouse.move(at.x, at.y);

  await expect(pointer(other, "Ada")).toHaveAttribute("data-edge", "bottom");
  await other.getByRole("button", { name: "Go to Ada" }).click();
  await expect(pointer(other, "Ada")).toHaveAttribute("data-edge", "");
  await context.close();
});

// A place between blocks has no caret of a line (the start of the
// document, before its first block): it is the top of the block there, a
// line high, not the whole editor, whose far corner is off the screen.
test("a place between blocks is the top of the block there, a line high", async ({ page }) => {
  const notebook = `notebook:${crypto.randomUUID()}`;
  await page.setViewportSize({ width: 1200, height: 900 });
  await open(page, notebook, "Ada");

  const { box, first, editor } = await page.evaluate(() => {
    const element = [...document.querySelectorAll("#notebook_one [data-issho-doc], #notebook_one")].find(
      (one) => (one as unknown as Record<symbol, unknown>)[Symbol.for("issho.locator")],
    ) as unknown as Record<symbol, (at: unknown) => DOMRect | null> & Element;
    const start = { node: "root", before: null, offset: 0 };
    const rect = element[Symbol.for("issho.locator")]({ anchor: start, focus: start });
    const editable = document.querySelector("#notebook_one .kotoba-editable")!;
    const block = editable.firstElementChild!.getBoundingClientRect();
    return {
      box: rect && { top: rect.top, height: rect.height },
      first: { top: block.top },
      editor: { height: editable.getBoundingClientRect().height },
    };
  });

  expect(box).not.toBeNull();
  expect(Math.abs(box!.top - first.top)).toBeLessThan(2);
  expect(box!.height).toBeLessThan(Math.min(60, editor.height));
});
