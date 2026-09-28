import { expect, test, type Locator, type Page } from "@playwright/test";

import { MOD, type JSONNode, expectNodes, openEditor, pasteData, readDocument, settle } from "./support";

const toolbar = (page: Page) => page.getByRole("toolbar", { name: "Formatting" });
const button = (page: Page, name: string) => toolbar(page).getByRole("button", { name, exact: true });
const live = (page: Page) => page.locator("#post_body_editor .kotoba-live");

/** The cells of the table in the hidden input: `headerState:text` for each cell, by row. */
async function grid(page: Page): Promise<string[][]> {
  const doc = await readDocument(page);
  const table = doc.root.children?.find((node) => node.type === "table");
  if (table === undefined) return [];
  const text = (node: JSONNode): string =>
    typeof node.text === "string" ? node.text : (node.children ?? []).map(text).join("");
  return (table.children ?? []).map((row) =>
    (row.children ?? []).map((cell) => `${cell.headerState as number}:${text(cell)}`),
  );
}

/** Clicks a cell of the editor's table, and waits for the editor to read the new caret. */
async function clickCell(page: Page, editable: Locator, row: number, column: number): Promise<void> {
  await editable.locator("tr").nth(row).locator("td, th").nth(column).click();
  await settle(page);
}

async function insertTable(page: Page, editable: Locator): Promise<void> {
  await editable.click();
  await button(page, "Table").click();
  await expect(editable.locator("table")).toBeVisible();
  await settle(page);
}

test("the Table button inserts a table with a header row, and Tab moves through its cells", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await page.keyboard.type("Before");
  await button(page, "Table").click();

  await expect(live(page)).toHaveText("Table inserted");
  await expect(editable.locator("tr")).toHaveCount(3);
  await expect(editable.locator("tr").first().locator("th")).toHaveCount(3);
  await expect(editable.locator("td")).toHaveCount(6);
  await expect(editable).toBeFocused();

  // The caret is in the first cell; Tab goes to the next one.
  await page.keyboard.type("Name");
  await page.keyboard.press("Tab");
  await page.keyboard.type("Role");
  await page.keyboard.press("Tab");
  await page.keyboard.press("Tab");
  await page.keyboard.type("Ada");
  await page.keyboard.press("Shift+Tab");
  await page.keyboard.type("Team");

  await expect
    .poll(() => grid(page))
    .toEqual([
      ["1:Name", "1:Role", "1:Team"],
      ["0:Ada", "0:", "0:"],
      ["0:", "0:", "0:"],
    ]);

  // Tab from the last cell goes after the table: the table is no trap.
  await clickCell(page, editable, 2, 2);
  await page.keyboard.press("Tab");
  await page.keyboard.type("After");
  await expect
    .poll(async () => (await readDocument(page)).root.children?.map((node) => node.type))
    .toEqual(["paragraph", "table", "paragraph"]);
  await expect(editable.locator("p").last()).toHaveText("After");
});

test("the table controls show in a table, and insert and delete rows and columns", async ({ page }) => {
  const editable = await openEditor(page);
  const tableGroup = toolbar(page).getByRole("group", { name: "Table" });
  await expect(tableGroup).toBeHidden();

  await insertTable(page, editable);
  await expect(tableGroup).toBeVisible();
  await expect(button(page, "Table")).toHaveAttribute("aria-disabled", "true");

  await clickCell(page, editable, 1, 0);
  await page.keyboard.type("a");
  await button(page, "Insert row below").click();
  await expect(live(page)).toHaveText("Row inserted");
  await expect(editable.locator("tr")).toHaveCount(4);

  // The caret stays in its cell when a row or a column is inserted.
  await page.keyboard.type("b");
  await button(page, "Insert column after").click();
  await expect(editable.locator("tr").first().locator("th")).toHaveCount(4);
  await page.keyboard.type("c");
  await button(page, "Insert column before").click();
  await button(page, "Insert row above").click();

  await expect
    .poll(() => grid(page))
    .toEqual([
      ["1:", "1:", "1:", "1:", "1:"],
      ["0:", "0:", "0:", "0:", "0:"],
      ["0:", "0:abc", "0:", "0:", "0:"],
      ["0:", "0:", "0:", "0:", "0:"],
      ["0:", "0:", "0:", "0:", "0:"],
    ]);

  await button(page, "Delete column").click();
  await expect(live(page)).toHaveText("Column deleted");
  await button(page, "Delete row").click();
  await expect(live(page)).toHaveText("Row deleted");
  await expect
    .poll(() => grid(page))
    .toEqual([
      ["1:", "1:", "1:", "1:"],
      ["0:", "0:", "0:", "0:"],
      ["0:", "0:", "0:", "0:"],
      ["0:", "0:", "0:", "0:"],
    ]);

  await page.keyboard.press(`${MOD}+Z`);
  await expect(editable.locator("tr")).toHaveCount(5);

  // Out of the table, the controls hide again.
  await editable.locator("p").last().click();
  await settle(page);
  await expect(tableGroup).toBeHidden();
  await expect(button(page, "Table")).toHaveAttribute("aria-disabled", "false");
});

test("Header row and Header column toggle the header cells", async ({ page }) => {
  const editable = await openEditor(page);
  await insertTable(page, editable);

  const headerRow = button(page, "Header row");
  const headerColumn = button(page, "Header column");
  await expect(headerRow).toHaveAttribute("aria-pressed", "true");
  await expect(headerColumn).toHaveAttribute("aria-pressed", "false");

  await headerColumn.click();
  await expect(headerColumn).toHaveAttribute("aria-pressed", "true");
  await expect(live(page)).toHaveText("Header column on");
  await expect(editable.locator("th")).toHaveCount(5);

  await headerRow.click();
  await expect(headerRow).toHaveAttribute("aria-pressed", "false");
  await expect(live(page)).toHaveText("Header row off");
  await expect
    .poll(async () => (await grid(page)).map((row) => row.map((cell) => cell.split(":")[0])))
    .toEqual([
      ["2", "0", "0"],
      ["2", "0", "0"],
      ["2", "0", "0"],
    ]);
});

test("Alt+F10 reaches the table controls from a cell; they act at the caret and give the focus back", async ({
  page,
}) => {
  const editable = await openEditor(page);
  await insertTable(page, editable);
  await clickCell(page, editable, 1, 0);
  await page.keyboard.type("x");

  // In a cell, Tab moves between cells; Alt+F10 goes to the toolbar.
  await page.keyboard.press("Alt+F10");
  await expect(toolbar(page).locator("button[tabindex='0']")).toBeFocused();
  await page.keyboard.press("End");
  await expect(button(page, "Redo")).toBeFocused();
  for (let i = 0; i < 9; i += 1) await page.keyboard.press("ArrowLeft");
  await expect(button(page, "Insert row below")).toBeFocused();
  await page.keyboard.press("Enter");

  await expect(editable).toBeFocused();
  await expect(live(page)).toHaveText("Row inserted");
  await page.keyboard.type("y");
  await expect.poll(async () => (await grid(page)).map((row) => row[0])).toEqual(["1:", "0:xy", "0:", "0:"]);

  await page.keyboard.press("Alt+F10");
  await page.keyboard.press("End");
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await expect(button(page, "Delete table")).toBeFocused();
  await page.keyboard.press("Enter");

  await expect(editable.locator("table")).toHaveCount(0);
  await expect(live(page)).toHaveText("Table deleted");
  await expect(editable).toBeFocused();
  await expect(toolbar(page).getByRole("group", { name: "Table" })).toBeHidden();
  await expect(toolbar(page).locator("button[tabindex='0']")).toHaveCount(1);
  await expectNodes(page, "table", 0);
});

test("a pasted HTML table becomes a table, with its merged cells split and no colours", async ({ page }) => {
  const editable = await openEditor(page);
  await editable.click();
  await pasteData(page, editable, {
    html:
      "<table><tr><th>Name</th><th>Role</th></tr>" +
      '<tr><td colspan="2" style="background-color: #ff0">Wide</td></tr></table>',
    text: "Name Role Wide",
  });

  const cells = await expectNodes(page, "tablecell", 4);
  for (const cell of cells) {
    expect(cell).toMatchObject({ colSpan: 1, rowSpan: 1, backgroundColor: null });
  }
  await expect.poll(async () => (await grid(page)).map((row) => row.map((cell) => cell.split(":")[1]))).toEqual([
    ["Name", "Role"],
    ["Wide", ""],
  ]);
});

test("a table is sent, stored and rendered, and loads from the server", async ({ page }) => {
  const editable = await openEditor(page);
  await insertTable(page, editable);
  await page.keyboard.type("Name");
  await page.keyboard.press("Tab");
  await page.keyboard.type("Role");
  await clickCell(page, editable, 1, 0);
  await page.keyboard.type("Ada | Lovelace");
  await expect.poll(async () => (await grid(page))[1][0]).toBe("0:Ada | Lovelace");

  const sent = await readDocument(page);
  await page.getByRole("button", { name: "Submit" }).click();

  const stored = page.locator("#stored-content");
  await expect(stored.locator(".kotoba-table-scroll > table.kotoba-table")).toBeVisible();
  await expect(stored.locator("thead th[scope='col']")).toHaveText(["Name", "Role", ""]);
  await expect(stored.locator("tbody tr").first().locator("td").first()).toHaveText("Ada | Lovelace");
  await expect(page.locator("#stored-text")).toContainText("Ada | Lovelace");
  const json = JSON.parse((await page.locator("#stored-json").textContent()) ?? "{}");
  expect(json.root).toEqual(sent.root);

  // A document from the server with a table loads into the editor.
  await page.getByRole("button", { name: "Load sample" }).click();
  await expect(editable.locator("h2")).toHaveText("Sample");
  await expect(editable.locator("th")).toHaveText(["Language", "Year"]);
  await expect(editable.locator("td")).toHaveText(["Elixir", "2012"]);
  await expectNodes(page, "table", 1);
});
