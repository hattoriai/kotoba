// Helpers for the browser tests.

import { crc32, deflateSync } from "node:zlib";

import { expect, type Locator, type Page } from "@playwright/test";

/** `Cmd` on macOS, `Ctrl` elsewhere, as the editor reads it. */
export const MOD = "ControlOrMeta";

export interface JSONNode {
  type: string;
  children?: JSONNode[];
  [key: string]: unknown;
}

export interface Envelope {
  kotoba: number;
  lexical: string;
  root: JSONNode;
}

/**
 * Opens a page and waits for the LiveView to connect and for the editor
 * `editorId` to mount. Returns the editable element.
 */
export async function openEditor(page: Page, path = "/", editorId = "post_body_editor"): Promise<Locator> {
  await page.goto(path);
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
  const editable = page.locator(`#${editorId} .kotoba-editable`);
  await expect(editable).toHaveAttribute("contenteditable", /true|false/);
  return editable;
}

/**
 * Waits for the browser to send its pending selection changes to the
 * editor. A key press that comes at once after a click or Shift+Arrow can
 * race Lexical's `selectionchange` handler, which a person never does.
 */
export async function settle(page: Page): Promise<void> {
  await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0))));
}

/** Moves the caret to the end of the document: Cmd+Down on macOS, Ctrl+End elsewhere. */
export async function documentEnd(page: Page): Promise<void> {
  await page.keyboard.press(process.platform === "darwin" ? "Meta+ArrowDown" : "Control+End");
}

/** Focuses the end of the editor. */
export async function focusEnd(page: Page, editable: Locator): Promise<void> {
  await editable.focus();
  await documentEnd(page);
}

/** Reads the document from the hidden input. */
export async function readDocument(page: Page, inputId = "post_body"): Promise<Envelope> {
  const value = await page.locator(`#${inputId}`).inputValue();
  return JSON.parse(value) as Envelope;
}

/** All nodes of a document, depth first. */
export function nodes(node: JSONNode): JSONNode[] {
  return [node, ...(node.children ?? []).flatMap(nodes)];
}

/** The nodes of the document in the hidden input, with a type. */
export async function nodesOfType(page: Page, type: string, inputId = "post_body"): Promise<JSONNode[]> {
  const doc = await readDocument(page, inputId);
  return nodes(doc.root).filter((node) => node.type === type);
}

/** Waits until the hidden input has a node of `type`, and returns the nodes. */
export async function expectNodes(page: Page, type: string, count: number, inputId = "post_body"): Promise<JSONNode[]> {
  await expect.poll(async () => (await nodesOfType(page, type, inputId)).length).toBe(count);
  return nodesOfType(page, type, inputId);
}

/** Collects the console messages of a page. */
export function collectConsole(page: Page): string[] {
  const messages: string[] = [];
  page.on("console", (message) => messages.push(`${message.type()}: ${message.text()}`));
  return messages;
}

/** Selects the last `count` characters before the caret. */
export async function selectBack(page: Page, count: number): Promise<void> {
  for (let i = 0; i < count; i += 1) await page.keyboard.press("Shift+ArrowLeft");
}

/** Pastes plain text into the focused editor with a real paste event. */
export async function pasteText(page: Page, editable: Locator, text: string): Promise<void> {
  // A paste event right after Shift+Arrow would race Lexical's selectionchange.
  await settle(page);
  await editable.evaluate((element, value) => {
    const data = new DataTransfer();
    data.setData("text/plain", value);
    element.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
  }, text);
}

export interface FileSpec {
  name: string;
  mimeType: string;
  buffer: Buffer;
}

/** A PNG image of the given size, one colour. */
export function png(name: string, width: number, height: number): FileSpec {
  const chunk = (type: string, data: Buffer): Buffer => {
    const length = Buffer.alloc(4);
    length.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([length, body, crc]);
  };

  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8; // bit depth
  header[9] = 2; // truecolour
  const row = Buffer.concat([Buffer.from([0]), Buffer.alloc(width * 3, 0x60)]);
  const pixels = Buffer.concat(Array.from({ length: height }, () => row));

  const buffer = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(pixels)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
  return { name, mimeType: "image/png", buffer };
}

/** Plain text that the upload does not accept. */
export function textFile(name: string): FileSpec {
  return { name, mimeType: "text/plain", buffer: Buffer.from("not an image\n") };
}

/**
 * Sends files to the editor with a `drop` or a `paste` event, as the
 * browser does when the user drops or pastes files.
 */
export async function sendFiles(editable: Locator, kind: "drop" | "paste", files: FileSpec[]): Promise<void> {
  const payload = files.map((file) => ({ name: file.name, type: file.mimeType, data: file.buffer.toString("base64") }));
  await editable.evaluate(
    (element, { kind, payload }) => {
      const data = new DataTransfer();
      for (const file of payload) {
        const bytes = Uint8Array.from(atob(file.data), (char) => char.charCodeAt(0));
        data.items.add(new File([bytes], file.name, { type: file.type }));
      }
      const rect = element.getBoundingClientRect();
      const init = { bubbles: true, cancelable: true };
      if (kind === "paste") {
        element.dispatchEvent(new ClipboardEvent("paste", { ...init, clipboardData: data }));
      } else {
        const point = { clientX: rect.left + 10, clientY: rect.top + 10 };
        element.dispatchEvent(new DragEvent("dragover", { ...init, ...point, dataTransfer: data }));
        element.dispatchEvent(new DragEvent("drop", { ...init, ...point, dataTransfer: data }));
      }
    },
    { kind, payload },
  );
}

/** Opens the file chooser from the toolbar's attach button and picks files. */
export async function attachFiles(page: Page, editorId: string, files: FileSpec[]): Promise<void> {
  const chooser = page.waitForEvent("filechooser");
  await page.locator(`#${editorId} [data-kotoba-command="upload"]`).click();
  await (await chooser).setFiles(files);
}

/** The id of the focused element, or its tag and class. */
export async function focused(page: Page): Promise<string> {
  return page.evaluate(() => {
    const element = document.activeElement;
    if (element === null) return "";
    return element.id !== "" ? `#${element.id}` : `${element.tagName.toLowerCase()}.${element.className}`;
  });
}
