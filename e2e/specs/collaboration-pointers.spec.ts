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
