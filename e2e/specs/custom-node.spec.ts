import { expect, test } from "@playwright/test";

import { collectConsole, expectNodes, openEditor } from "./support";

test("the Tag node loads through data-nodes and round-trips", async ({ page }) => {
  const messages = collectConsole(page);
  const editable = await openEditor(page);
  await expect(page.locator("#post_body_editor")).toHaveAttribute("data-nodes", "/assets/nodes/tag.js");

  await editable.click();
  await page.keyboard.type("Label: ");
  await page.getByRole("button", { name: "Insert tag" }).click();

  // decorate() returned the element that the editor mounted.
  const tag = editable.locator("span.dev-tag");
  await expect(tag).toHaveText("urgent");
  await expect(tag).toHaveAttribute("contenteditable", "false");
  const [node] = await expectNodes(page, "dev-tag", 1);
  expect(node).toEqual({ type: "dev-tag", version: 1, label: "urgent" });

  await page.getByRole("button", { name: "Submit" }).click();
  // The server renders it through KotobaDev.Nodes.Tag (config :kotoba, nodes:).
  await expect(page.locator("#stored-content span.dev-tag")).toHaveText("urgent");
  await expect(page.locator("#stored-text")).toHaveText("Label: urgent");
  const stored = JSON.parse((await page.locator("#stored-json").textContent()) ?? "{}");
  expect(JSON.stringify(stored)).toContain('{"label":"urgent","type":"dev-tag","version":1}');

  expect(messages.filter((message) => message.startsWith("error"))).toEqual([]);
});

test("a stored Tag node loads into the editor", async ({ page }) => {
  const editable = await openEditor(page, "/?sample=1");
  await expect(editable.locator("span.dev-tag")).toHaveText("sample");
  await expectNodes(page, "dev-tag", 1);
});

test("an app node with a built-in type is refused with a log, and the editor mounts", async ({ page }) => {
  const messages = collectConsole(page);
  const editable = await openEditor(page, "/nodes?case=builtin", "nodes_body_editor");

  await expect
    .poll(() => messages)
    .toContainEqual('error: Kotoba: the node type "mention" is built in; the app node is not registered');
  await editable.click();
  await page.keyboard.type("still works");
  await expect(editable).toHaveText("still works");
});

test("a node module that does not load is logged, and the editor mounts", async ({ page }) => {
  const messages = collectConsole(page);
  const editable = await openEditor(page, "/nodes?case=missing", "nodes_body_editor");

  await expect
    .poll(() => messages.some((message) => message.startsWith("error: Kotoba: could not load the node module /assets/nodes/missing.js")))
    .toBe(true);
  await editable.click();
  await page.keyboard.type("still works");
  await expect(editable).toHaveText("still works");
});
