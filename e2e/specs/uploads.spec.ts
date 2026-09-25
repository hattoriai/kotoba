import { expect, test, type Locator } from "@playwright/test";

import { attachFiles, documentEnd, expectNodes, nodes, openEditor, png, readDocument, sendFiles, settle, textFile, type Envelope } from "./support";

const EDITOR = "post_body_editor";

// The blocks of the document: the first text of each paragraph, or the name
// of each attachment.
function blocks(doc: Envelope): string[] {
  return doc.root
    .children!.map((node) =>
      node.type === "attachment" ? String(node.name) : nodes(node).find((child) => child.type === "text")?.text,
    )
    .filter((entry): entry is string => entry !== undefined);
}

// Holds two uploads at the end of "one", deletes the marker of the first
// from the keyboard, and moves the caret to the end of "two".
async function holdTwoAndDeleteFirstMarker(page: import("@playwright/test").Page, reject: boolean) {
  const editable = await openEditor(page);
  await page.getByLabel("Hold uploads").check();
  if (reject) await page.getByLabel("Reject next upload").check();

  await editable.click();
  await page.keyboard.type("one");
  await page.keyboard.press("Enter");
  await page.keyboard.type("two");
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("End");
  await settle(page);
  await attachFiles(page, EDITOR, [png("a.png", 2, 2), png("b.png", 3, 3)]);
  const markers = editable.locator(".kotoba-upload-marker");
  await expect(markers).toHaveText(["Uploading a.png…", "Uploading b.png…"]);
  await expect(page.locator("#held-count")).toHaveText("2");

  // Put the caret after "one", before marker a, and delete marker a with
  // the keyboard.
  const one = editable.getByText("one", { exact: true });
  const box = (await one.boundingBox())!;
  await one.click({ position: { x: box.width - 1, y: box.height / 2 } });
  await settle(page);
  await page.keyboard.press("Delete");
  await expect(markers).toHaveText(["Uploading b.png…"]);

  // The caret goes to the end of "two".
  await documentEnd(page);
  await settle(page);
  await expect(editable.locator("p").last()).toHaveText("two");
  return editable;
}

async function expectImage(image: Locator, width: number): Promise<void> {
  await expect(image).toHaveAttribute("src", /^\/uploads\/kotoba\/.+\.png$/);
  // The image is served by Kotoba.Storage.Local.Plug.
  await expect.poll(() => image.evaluate((element) => (element as HTMLImageElement).naturalWidth)).toBe(width);
}

test("the attach button uploads an image and inserts it at the caret", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Before");
  await page.keyboard.press("Enter");
  await page.keyboard.type("After");
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("End");

  await attachFiles(page, EDITOR, [png("pixel.png", 2, 2)]);

  const image = editable.locator("figure.kotoba-attachment-figure img");
  await expectImage(image, 2);
  await expect(image).toHaveAttribute("alt", "pixel.png");
  await expect(editable.locator(".kotoba-upload-marker")).toHaveCount(0);

  const [attachment] = await expectNodes(page, "attachment", 1);
  expect(attachment).toMatchObject({ name: "pixel.png", contentType: "image/png", width: 2, height: 2 });

  // The attachment sits after "Before" and before "After".
  const doc = await readDocument(page);
  const order = doc.root.children!.map((node) =>
    node.type === "attachment" ? "attachment" : nodes(node).find((child) => child.type === "text")?.text,
  );
  expect(order.filter((entry) => entry !== undefined)).toEqual(["Before", "attachment", "After"]);
});

test("a dropped image is uploaded", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await sendFiles(editable, "drop", [png("dropped.png", 3, 2)]);

  await expectImage(editable.locator("img.kotoba-attachment-image"), 3);
  const [attachment] = await expectNodes(page, "attachment", 1);
  expect(attachment).toMatchObject({ name: "dropped.png", width: 3, height: 2 });
});

test("a pasted image is uploaded", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Pasted: ");
  await sendFiles(editable, "paste", [png("pasted.png", 4, 1)]);

  await expectImage(editable.locator("img.kotoba-attachment-image"), 4);
  const [attachment] = await expectNodes(page, "attachment", 1);
  expect(attachment).toMatchObject({ name: "pasted.png", width: 4, height: 1 });
});

test("uploads that finish out of order take the place of their own markers", async ({ page }) => {
  // With uploads=reverse, the server waits for both files and stores the
  // second first; each attachment names its upload entry (`ref`).
  const editable = await openEditor(page, "/?uploads=reverse");
  await editable.click();
  await attachFiles(page, EDITOR, [png("first.png", 5, 5), png("second.png", 7, 7)]);

  const attachments = await expectNodes(page, "attachment", 2);
  expect(attachments.map((node) => [node.name, node.width])).toEqual([
    ["first.png", 5],
    ["second.png", 7],
  ]);
  await expect(editable.locator(".kotoba-upload-marker")).toHaveCount(0);
  await expect(editable.locator("img.kotoba-attachment-image")).toHaveCount(2);
});

test("an upload whose marker the user deleted goes to the selection, not to another marker", async ({ page }) => {
  const editable = await holdTwoAndDeleteFirstMarker(page, false);
  await page.getByRole("button", { name: "Release" }).click();

  await expectNodes(page, "attachment", 2);
  await expect(editable.locator(".kotoba-upload-marker")).toHaveCount(0);
  // b takes its own marker's place; a, whose marker is gone, goes to the
  // selection (after "two").
  expect(blocks(await readDocument(page))).toEqual(["one", "b.png", "two", "a.png"]);
});

test("a rejected upload whose marker the user deleted inserts nothing and leaves the other marker", async ({
  page,
}) => {
  const editable = await holdTwoAndDeleteFirstMarker(page, true);
  await page.getByRole("button", { name: "Release" }).click();

  const [attachment] = await expectNodes(page, "attachment", 1);
  expect(attachment?.name).toBe("b.png");
  await expect(editable.locator(".kotoba-upload-marker")).toHaveCount(0);
  expect(blocks(await readDocument(page))).toEqual(["one", "b.png", "two"]);
});

test("a rejected upload loses its marker, and no other marker is replaced", async ({ page }) => {
  const editable = await openEditor(page);
  await page.getByLabel("Hold uploads").check();
  await page.getByLabel("Reject next upload").check();
  await editable.click();
  await attachFiles(page, EDITOR, [png("rejected.png", 2, 2)]);
  await expect(page.locator("#held-count")).toHaveText("1");
  await page.getByRole("button", { name: "Release" }).click();

  await expect(editable.locator(".kotoba-upload-marker")).toHaveCount(0);
  await expect(page.getByLabel("Reject next upload")).not.toBeChecked();
  await page.waitForTimeout(300);
  expect(nodes((await readDocument(page)).root).map((node) => node.type)).not.toContain("attachment");
});

test("a file that the upload does not accept loses its marker", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Text ");
  await editable.evaluate((element) => {
    const seen = new MutationObserver(() => {
      const marker = element.querySelector(".kotoba-upload-marker");
      if (marker !== null) {
        element.dataset.sawMarker = marker.textContent ?? "";
        seen.disconnect();
      }
    });
    seen.observe(element, { childList: true, subtree: true, characterData: true });
  });
  await sendFiles(editable, "drop", [textFile("notes.txt")]);

  // The marker shows, then the server cancels the entry and removes it.
  await expect(editable).toHaveAttribute("data-saw-marker", "Uploading notes.txt…");
  await expect(page.locator("#validate-count")).not.toHaveText("0");
  await expect(editable.locator(".kotoba-upload-marker")).toHaveCount(0);
  await expect(editable.locator("figure")).toHaveCount(0);
  expect(nodes((await readDocument(page)).root).map((node) => node.type)).not.toContain("attachment");

  // The editor still takes an accepted file after that.
  await sendFiles(editable, "drop", [png("ok.png", 1, 1)]);
  await expectNodes(page, "attachment", 1);
});

test("a PDF becomes a file attachment, not an image", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  const pdf = { name: "paper.pdf", mimeType: "application/pdf", buffer: Buffer.from("%PDF-1.4\n%%EOF\n") };
  await attachFiles(page, EDITOR, [pdf]);

  await expect(editable.locator(".kotoba-attachment-name")).toHaveText("paper.pdf");
  await expect(editable.locator(".kotoba-attachment-icon")).toHaveText("PDF");
  await expect(editable.locator("img.kotoba-attachment-image")).toHaveCount(0);
  const [attachment] = await expectNodes(page, "attachment", 1);
  expect(attachment).toMatchObject({ contentType: "application/pdf", url: expect.stringMatching(/\.pdf$/) });
});
