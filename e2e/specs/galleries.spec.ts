import { expect, test, type Page } from "@playwright/test";

import { MOD, attachFiles, expectNodes, openEditor, png, readDocument, settle, type JSONNode } from "./support";

const EDITOR = "post_body_editor";
const live = (page: Page) => page.locator(`#${EDITOR} .kotoba-live`);
const toolbar = (page: Page) => page.locator(`#${EDITOR}`).getByRole("toolbar", { name: "Formatting" });
const button = (page: Page, name: string) => toolbar(page).getByRole("button", { name, exact: true });
const images = (page: Page) => page.locator(`#${EDITOR} .kotoba-gallery .kotoba-attachment`);

// The top-level blocks: a gallery as the names of its files.
async function blocks(page: Page): Promise<(string | string[])[]> {
  return (await readDocument(page)).root.children!.map((node: JSONNode) =>
    node.type === "gallery"
      ? node.children!.map((child) => String(child.name))
      : node.type === "attachment"
        ? String(node.name)
        : node.type,
  );
}

async function galleryOf(page: Page, names: string[]): Promise<void> {
  await attachFiles(page, EDITOR, names.map((name, index) => png(name, index + 1, index + 1)));
  await expectNodes(page, "attachment", names.length);
}

test("images uploaded together make a gallery, in their order when the uploads finish in another", async ({
  page,
}) => {
  // With uploads=reverse, the server stores the last file first.
  const editable = await openEditor(page, "/?uploads=reverse");
  await editable.click();
  await page.keyboard.type("Photos");
  await galleryOf(page, ["a.png", "b.png", "c.png"]);

  await expect.poll(() => blocks(page)).toEqual(["paragraph", ["a.png", "b.png", "c.png"], "paragraph"]);
  await expect(editable.locator(".kotoba-upload-marker")).toHaveCount(0);
  await expect(images(page).locator("img")).toHaveCount(3);

  // Stored, rendered, and loaded again, with the same order.
  await page.getByRole("button", { name: "Submit" }).click();
  const stored = page.locator("#stored-content .kotoba-gallery figure img");
  await expect(stored).toHaveCount(3);
  expect(await stored.evaluateAll((all) => all.map((image) => image.getAttribute("alt")))).toEqual([
    "a.png",
    "b.png",
    "c.png",
  ]);
  await page.getByRole("button", { name: "Load sample" }).click();
  await expect.poll(() => blocks(page)).not.toContainEqual(["a.png", "b.png", "c.png"]);
  await page.getByRole("button", { name: "Load stored" }).click();
  await expect.poll(() => blocks(page)).toEqual(["paragraph", ["a.png", "b.png", "c.png"], "paragraph"]);
  await expect(images(page)).toHaveCount(3);
});

test("the arrow keys move between the images and out of the gallery; Alt+arrows move an image", async ({
  page,
}) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Before");
  await galleryOf(page, ["a.png", "b.png", "c.png"]);

  await images(page).first().click();
  await expect(images(page).first()).toHaveClass(/kotoba-selected/);
  await page.keyboard.press("ArrowRight");
  await expect(live(page)).toHaveText("2 of 3: b.png");
  await page.keyboard.press("ArrowRight");
  await expect(live(page)).toHaveText("3 of 3: c.png");

  // Past the last image: the caret goes to the paragraph after the gallery.
  await page.keyboard.press("ArrowRight");
  await page.keyboard.type("After");
  await expect.poll(() => blocks(page)).toEqual(["paragraph", ["a.png", "b.png", "c.png"], "paragraph"]);
  await expect(editable.locator("p").last()).toHaveText("After");

  // Back into the gallery from the start of that paragraph.
  await page.keyboard.press("Home");
  await page.keyboard.press("ArrowLeft");
  await expect(live(page)).toHaveText("3 of 3: c.png");
  await expect(images(page).nth(2)).toHaveClass(/kotoba-selected/);

  await page.keyboard.press("Alt+ArrowLeft");
  await expect(live(page)).toHaveText("Moved to 2 of 3: c.png");
  await page.keyboard.press("Alt+ArrowLeft");
  await expect(live(page)).toHaveText("Moved to 1 of 3: c.png");
  await page.keyboard.press("Alt+ArrowLeft");
  await expect(live(page)).toHaveText("Already the first image");
  await expect.poll(() => blocks(page)).toEqual(["paragraph", ["c.png", "a.png", "b.png"], "paragraph"]);

  // Each move is an undo step.
  await page.keyboard.press(`${MOD}+Z`);
  await expect.poll(() => blocks(page)).toEqual(["paragraph", ["a.png", "c.png", "b.png"], "paragraph"]);

  // Past the first image: the caret goes to the end of "Before".
  await images(page).first().click();
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.type("!");
  await expect(editable.locator("p").first()).toHaveText("Before!");
});

test("Backspace and Delete remove an image; a gallery of one image becomes that image", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await galleryOf(page, ["a.png", "b.png", "c.png"]);

  await images(page).nth(1).click();
  await page.keyboard.press("Backspace");
  await expect(live(page)).toHaveText("Removed b.png");
  await expect(images(page).first()).toHaveClass(/kotoba-selected/);

  await page.keyboard.press("Delete");
  await expect(live(page)).toHaveText("Removed a.png");
  await expect.poll(() => blocks(page)).toEqual(["paragraph", "c.png", "paragraph"]);
  await expect(editable.locator(".kotoba-attachment.kotoba-selected")).toHaveCount(1);

  await page.keyboard.press(`${MOD}+Z`);
  await expect.poll(() => blocks(page)).toEqual(["paragraph", ["a.png", "c.png"], "paragraph"]);
  await page.keyboard.press(`${MOD}+Z`);
  await expect.poll(() => blocks(page)).toEqual(["paragraph", ["a.png", "b.png", "c.png"], "paragraph"]);
});

test("the Image group of the toolbar groups images, moves them and ungroups them", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Text");
  await attachFiles(page, EDITOR, [png("a.png", 2, 2)]);
  await expectNodes(page, "attachment", 1);
  await attachFiles(page, EDITOR, [png("b.png", 3, 3)]);
  await expectNodes(page, "attachment", 2);
  expect(await blocks(page)).toEqual(["paragraph", "a.png", "b.png"]);

  // The group shows when an image is selected.
  const gallery = button(page, "Gallery");
  await expect(gallery).toBeHidden();
  await editable.locator(".kotoba-attachment").first().click();
  await expect(gallery).toBeVisible();
  await expect(gallery).toHaveAttribute("aria-pressed", "false");
  await expect(button(page, "Move image left")).toHaveAttribute("aria-disabled", "true");

  await gallery.click();
  await expect(live(page)).toHaveText("Gallery of 2 images");
  await expect.poll(() => blocks(page)).toEqual(["paragraph", ["a.png", "b.png"]]);
  await expect(gallery).toHaveAttribute("aria-pressed", "true");
  await expect(button(page, "Move image left")).toHaveAttribute("aria-disabled", "true");
  await expect(button(page, "Move image right")).toHaveAttribute("aria-disabled", "false");

  await button(page, "Move image right").click();
  await expect(live(page)).toHaveText("Moved to 2 of 2: a.png");
  await expect.poll(() => blocks(page)).toEqual(["paragraph", ["b.png", "a.png"]]);
  await expect(button(page, "Move image right")).toHaveAttribute("aria-disabled", "true");

  await gallery.click();
  await expect(live(page)).toHaveText("Gallery ungrouped");
  await expect.poll(() => blocks(page)).toEqual(["paragraph", "b.png", "a.png"]);

  // Out of an image, the group hides again.
  await editable.locator("p").first().click();
  await settle(page);
  await expect(gallery).toBeHidden();
});

test("an image uploaded while an image of a gallery is selected joins the gallery after it", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await galleryOf(page, ["a.png", "b.png"]);

  await images(page).first().click();
  await attachFiles(page, EDITOR, [png("c.png", 4, 4)]);
  await expectNodes(page, "attachment", 3);
  await expect.poll(() => blocks(page)).toEqual(["paragraph", ["a.png", "c.png", "b.png"], "paragraph"]);
});
