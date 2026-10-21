import { expect, test, type Page } from "@playwright/test";
import { focusEnd, openEditor } from "./support";

// An agent in a notebook, over MCP (the dev app's /mcp, called through Sake's client): the person
// sees it in the room, sees its selection, sees it type, and their edits merge with its own.
const editor = (page: Page, block: string) => page.locator(`#notebook_${block} .kotoba-editable`);
const carets = (page: Page, block: string) => page.locator(`#notebook_${block} .kotoba-collab-caret`);

async function open(page: Page, notebook: string, name: string): Promise<void> {
  await openEditor(page, `/collab/notebook?document=${notebook}&name=${name}`, "notebook_one");
  for (const block of ["one", "two"]) await expect(page.locator(`#notebook_${block} [data-collab-status]`)).toHaveText("Saved");
}

async function agent(page: Page, tool: string, args: Record<string, unknown>): Promise<unknown> {
  const response = await page.request.post("/dev/agent", { data: { tool, arguments: args } });
  const reply = await response.json() as { result?: unknown; error?: string };
  if (reply.error) throw new Error(`${tool}: ${reply.error}`);
  return reply.result;
}

test("an agent works in a notebook as a person does, and the person sees it", async ({ page }) => {
  const notebook = `notebook:${crypto.randomUUID()}`;
  const one = `${notebook}/one`;
  const two = `${notebook}/two`;
  await open(page, notebook, "Ada");

  // It types; Ada sees it written, and sees it in the room.
  await agent(page, "type_text", { document: one, at: "end", text: "Read the docs today" });
  await expect(editor(page, "one")).toHaveText("Read the docs today");
  await expect(page.getByRole("list", { name: "People here" })).toContainText("Claude Code, an agent");

  // It selects; Ada sees its selection, with its name.
  await agent(page, "select_text", { document: one, text: "the docs" });
  await expect(carets(page, "one")).toHaveCount(1);
  await expect(carets(page, "one")).toContainText("Claude Code");
  await expect(page.locator("#notebook_one .kotoba-collab-selection").first()).toBeVisible();

  // It makes the selection a link, and formats a word.
  await agent(page, "link_text", { document: one, url: "https://kotoba.dev" });
  await expect(editor(page, "one").locator('a[href="https://kotoba.dev"]')).toHaveText("the docs");
  await agent(page, "format_text", { document: one, text: "today", marks: { bold: true } });
  await expect(editor(page, "one").locator("strong")).toHaveText("today");

  // Ada and the agent write at the same time, in two editors.
  await focusEnd(page, editor(page, "two"));
  const typing = agent(page, "type_text", { document: one, after: "today", text: ", and tomorrow" });
  await page.keyboard.type("Ada was here");
  await typing;
  await expect(editor(page, "one")).toHaveText("Read the docs today, and tomorrow");
  await expect(editor(page, "two")).toHaveText("Ada was here");

  // It copies a passage with its link and pastes it in the other editor.
  await agent(page, "copy_text", { document: one, text: "Read the docs" });
  await agent(page, "paste_text", { document: two, at: "end" });
  await expect(editor(page, "two")).toHaveText("Ada was hereRead the docs");
  await expect(editor(page, "two").locator("strong")).toHaveCount(0);

  // Its cursor went with it, to the other editor.
  await expect(carets(page, "two")).toHaveCount(1);
  await expect(carets(page, "one")).toHaveCount(0);
  for (const block of ["one", "two"]) await expect(page.locator(`#notebook_${block} [data-collab-status]`)).toHaveText("Saved");
});
