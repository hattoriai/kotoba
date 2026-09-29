import { expect, test, type Page } from "@playwright/test";

import { attachFiles, brokenWebm, expectNodes, openEditor, pdf, webm } from "./support";

const EDITOR = "post_body_editor";
const editor = (page: Page) => page.locator(`#${EDITOR}`);

test("a PDF shows in the browser's viewer, and saves as an object with a download link", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await attachFiles(page, EDITOR, [pdf("report.pdf")]);

  const [node] = await expectNodes(page, "attachment", 1);
  expect(node).toMatchObject({ name: "report.pdf", contentType: "application/pdf" });
  const url = String(node?.url);
  expect(url).toMatch(/^\/uploads\/kotoba\/.+\.pdf$/);

  // In the editor: the viewer, out of the tab order, named after the file.
  const viewer = editor(page).locator(".kotoba-attachment-pdf object.kotoba-attachment-viewer");
  await expect(viewer).toHaveAttribute("data", url);
  await expect(viewer).toHaveAttribute("type", "application/pdf");
  await expect(viewer).toHaveAttribute("tabindex", "-1");
  await expect(viewer).toHaveAttribute("aria-label", "report.pdf");

  // The file is served inline, with the strict headers.
  const response = await page.request.get(url);
  expect(response.headers()["content-type"]).toBe("application/pdf");
  expect(response.headers()["content-disposition"]).toBe("inline");
  expect(response.headers()["content-security-policy"]).toBe("default-src 'none'; sandbox");

  // Saved: an object with a download link inside, and one in the caption.
  await page.getByRole("button", { name: "Submit" }).click();
  const stored = page.locator("#stored-content figure.kotoba-attachment-pdf");
  await expect(stored.locator('object[type="application/pdf"]')).toHaveAttribute("data", url);
  await expect(stored.locator("object a[download]")).toHaveAttribute("href", url);
  await expect(stored.locator("figcaption a[download]")).toHaveText("report.pdf");
});

test("a video plays with controls, loads its metadata only, and survives a save and a reload", async ({
  page,
  browserName,
}) => {
  const editable = await openEditor(page);
  await editable.click();
  await attachFiles(page, EDITOR, [webm("clip.webm")]);

  const [node] = await expectNodes(page, "attachment", 1);
  expect(node).toMatchObject({ name: "clip.webm", contentType: "video/webm" });
  const url = String(node?.url);

  const player = editor(page).locator(".kotoba-attachment-video video.kotoba-attachment-player");
  const file = editor(page).locator(".kotoba-attachment-failed");

  // Chromium and Firefox play WebM. WebKit may not: the editor then shows
  // the file (see the next test).
  if (browserName === "webkit") {
    await expect(player.or(file)).toBeVisible();
  } else {
    await expect(player).toHaveAttribute("src", url);
    await expect(player).toHaveAttribute("preload", "metadata");
    await expect(player).toHaveAttribute("tabindex", "-1");
    expect(await player.evaluate((video: HTMLVideoElement) => [video.controls, video.autoplay])).toEqual([
      true,
      false,
    ]);
    await expect.poll(() => player.evaluate((video: HTMLVideoElement) => video.readyState)).toBeGreaterThan(0);
  }

  // The file is served inline, with byte ranges for seeking.
  const whole = await page.request.get(url);
  expect(whole.headers()["content-type"]).toBe("video/webm");
  expect(whole.headers()["accept-ranges"]).toBe("bytes");
  const part = await page.request.get(url, { headers: { Range: "bytes=0-3" } });
  expect(part.status()).toBe(206);
  expect(part.headers()["content-range"]).toMatch(/^bytes 0-3\/\d+$/);
  expect([...(await part.body())]).toEqual([0x1a, 0x45, 0xdf, 0xa3]);

  // Saved, rendered, and loaded again.
  await page.getByRole("button", { name: "Submit" }).click();
  const stored = page.locator("#stored-content figure.kotoba-attachment-video video");
  await expect(stored).toHaveAttribute("src", url);
  await expect(stored).toHaveAttribute("preload", "metadata");
  expect(await stored.evaluate((video: HTMLVideoElement) => [video.controls, video.autoplay])).toEqual([true, false]);
  await expect(stored.locator("a[download]")).toHaveAttribute("href", url);

  await page.getByRole("button", { name: "Load sample" }).click();
  await expect(editor(page).locator(".kotoba-attachment-video")).toHaveCount(0);
  await page.getByRole("button", { name: "Load stored" }).click();
  if (browserName === "webkit") await expect(player.or(file)).toBeVisible();
  else await expect(player).toHaveAttribute("src", url);
});

test("a video that the browser cannot play shows as a file", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await attachFiles(page, EDITOR, [brokenWebm("broken.webm")]);

  const [node] = await expectNodes(page, "attachment", 1);
  expect(node).toMatchObject({ contentType: "video/webm" });

  const failed = editor(page).locator(".kotoba-attachment-failed");
  await expect(failed.locator(".kotoba-attachment-icon")).toHaveText("WEBM");
  await expect(editor(page).locator("video")).toHaveCount(0);
  await expect(failed.locator(".kotoba-attachment-name")).toHaveText("broken.webm");
});

test("a file that claims to be a video but is not is a download", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  const fake = { name: "fake.mp4", mimeType: "video/mp4", buffer: Buffer.from("<script>alert(1)</script>") };
  await attachFiles(page, EDITOR, [fake]);

  const [node] = await expectNodes(page, "attachment", 1);
  expect(node).toMatchObject({ name: "fake.mp4", contentType: "application/octet-stream" });
  expect(String(node?.url)).toMatch(/\.bin$/);
  await expect(editor(page).locator("video")).toHaveCount(0);
  await expect(editor(page).locator(".kotoba-attachment-icon")).toHaveText("MP4");

  const response = await page.request.get(String(node?.url));
  expect(response.headers()["content-disposition"]).toBe("attachment");
});
