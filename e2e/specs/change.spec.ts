import { expect, test } from "@playwright/test";

import { expectNodes, openEditor } from "./support";

// `kotoba:change` is opt-in: the editor pushes it only with the component's
// `change` attribute (`data-change="true"`). The form data has the document
// in every case.

test("without change, typing pushes no kotoba:change", async ({ page }) => {
  const editable = await openEditor(page);
  await expect(page.locator("#post_body_editor")).toHaveAttribute("data-change", "false");
  await editable.click();
  await page.keyboard.type("Not pushed");
  await expectNodes(page, "text", 1);

  // Longer than the 300 ms debounce, and a blur, which flushes a pending push.
  await page.waitForTimeout(700);
  await page.locator("#submit").focus();
  await page.waitForTimeout(200);
  await expect(page.locator("#change-count")).toHaveText("0");

  // The form still gets the document.
  await page.locator("#submit").click();
  await expect(page.locator("#stored-text")).toHaveText("Not pushed");
});

test("with change, typing pushes kotoba:change", async ({ page }) => {
  const editable = await openEditor(page, "/?change=1");
  await expect(page.locator("#post_body_editor")).toHaveAttribute("data-change", "true");
  await editable.click();
  await page.keyboard.type("Pushed");
  await expect(page.locator("#change-count")).not.toHaveText("0");
});

test("a patch of the change attribute turns the pushes on and off", async ({ page }) => {
  const editable = await openEditor(page);
  const pushChanges = page.getByRole("checkbox", { name: "Push changes" });

  await pushChanges.check();
  await expect(page.locator("#post_body_editor")).toHaveAttribute("data-change", "true");
  await editable.click();
  await page.keyboard.type("on");
  await expect(page.locator("#change-count")).not.toHaveText("0");
  await page.waitForTimeout(500);
  const pushed = await page.locator("#change-count").textContent();

  await pushChanges.uncheck();
  await expect(page.locator("#post_body_editor")).toHaveAttribute("data-change", "false");
  await editable.click();
  await page.keyboard.type(" off");
  await page.waitForTimeout(700);
  await page.locator("#submit").focus();
  await page.waitForTimeout(200);
  await expect(page.locator("#change-count")).toHaveText(pushed ?? "");
});
