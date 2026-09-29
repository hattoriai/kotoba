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

/** What a paste carries: HTML, plain text and files. */
export interface Clipboard {
  html?: string;
  text?: string;
  files?: FileSpec[];
}

/**
 * Pastes into the editor with a paste event, as the browser sends it for
 * Cmd/Ctrl+V: the clipboard data is in the event's `clipboardData`.
 */
export async function pasteData(page: Page, editable: Locator, clipboard: Clipboard): Promise<void> {
  // A paste event right after Shift+Arrow would race Lexical's selectionchange.
  await settle(page);
  const files = (clipboard.files ?? []).map((file) => ({
    name: file.name,
    type: file.mimeType,
    data: file.buffer.toString("base64"),
  }));
  await editable.evaluate(
    (element, { html, text, files }) => {
      const data = new DataTransfer();
      if (html !== undefined) data.setData("text/html", html);
      if (text !== undefined) data.setData("text/plain", text);
      for (const file of files) {
        const bytes = Uint8Array.from(atob(file.data), (char) => char.charCodeAt(0));
        data.items.add(new File([bytes], file.name, { type: file.type }));
      }
      const event = new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true });
      // Firefox leaves out the `clipboardData` of the event's init: the
      // event then carries the data as a property of its own.
      if (event.clipboardData !== data) Object.defineProperty(event, "clipboardData", { value: data });
      element.dispatchEvent(event);
    },
    { html: clipboard.html, text: clipboard.text, files },
  );
}

/** Pastes plain text into the editor. */
export async function pasteText(page: Page, editable: Locator, text: string): Promise<void> {
  await pasteData(page, editable, { text });
}

export interface FileSpec {
  name: string;
  mimeType: string;
  buffer: Buffer;
}

/** A PNG image of the given size, one colour. */
/** A small PDF file. */
export function pdf(name: string): FileSpec {
  return { name, mimeType: "application/pdf", buffer: Buffer.from("%PDF-1.4\n%%EOF\n") };
}

// A WebM video of 32 × 24 pixels, 0.8 s long, recorded by Chromium's
// MediaRecorder from a canvas (VP8).
const TINY_WEBM =
  "GkXfo59ChoEBQveBAULygQRC84EIQoKEd2VibUKHgQRChYECGFOAZwEAAAAAAANZEU2bdLlNu4tTq4QVSalmU6yBbk27i1OrhBZU" +
  "rmtTrIGTTbuLU6uEH0O2dVOsgcFNu4xTq4QcU7trU6yCA0fsrgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
  "AAAAAAAAAAAVSalmoCrXsYMPQkBEiYREL6XDTYCGQ2hyb21lV0GGQ2hyb21lFlSua6mup9eBAXPFh9Wd/ouRAtmDgQFV7oEBhoVW" +
  "X1ZQOOCKsIEguoEYU8CBAR9DtnUBAAAAAAACeueBAKDkobmBAAAA0AIAnQEqIAAYAAJHCIWFiJmEiAyCAnWqA/gCCCEpnnD+8QqP" +
  "/6gz5BnyDP1Uv/nYNiXa8AB1oaampO6BAaWfMAIAnQEqIAAYAAcHCIWFiJmEiCYCAAeQ88nA/vBdAKDIoaiBAGQA0QEACRCAABgA" +
  "Hlf0DABBDgD+7nZ//lnz+Gzqc/uQH0jn0q3YdaGYppbugQGlkbEBABwRPAAYABhYL/QACHAA+4EAoMqhqoEAyADRAQAJEFQAGAAe" +
  "V/QMAEEOAP7vdtf+hJ+CT8En7p/8aY8/A9AM0HWhmKaW7oEBpZGxAQAcESwAGAAYWC/0AAhwAPuBZKDJoamBASwA0QEACRBEABgA" +
  "Hlf0DABBDgD+7c7f/pNnibPE2fJI4Hh+Hh+G6HWhmKaW7oEBpZGxAQAcERwAGAAYWC/0AAhwAPuByKDIoaeBAZEA0QEACRA4ABgA" +
  "Hlf0DABBDgD+6tR//SbPE2eJs+SL1Qb4FoB1oZimlu6BAaWRsQEAHBDsABgAGFgv9AAIcAD7ggEsoMyhq4EB9QDRAQAJECwAGAAe" +
  "V/QMAEEOAP7hw3/6tD5aHy0P3Pv9uo/M8fm1NAB1oZimlu6BAaWRsQEAHBDcABgAGFgv9AAIcAD7ggGRoMqhqYECWgARAgAJECQA" +
  "GAcwCCF6cs1ASIYA/Mr/6s+mhF/aR/+k0ap+PsgAdaGYppbugQGlkbEBABwQwAAYABhYL/QACHAA+4IB9aDKoamBAr4A0QEACRB0" +
  "FGAAeV/QMAEEOAD+wM/6sp7q57ssa/8bqk3VJvGygHWhmKaW7oEBpZGxAQAcEIgUYABhYL/QACHAAPuCAlocU7trjbuLs4EAt4b3" +
  "gQHxgcE=";

/** A small WebM video that browsers can play. */
export function webm(name: string): FileSpec {
  return { name, mimeType: "video/webm", buffer: Buffer.from(TINY_WEBM, "base64") };
}

/**
 * A file that starts as a WebM (the server takes it as one) but has no
 * video: the browser cannot play it.
 */
export function brokenWebm(name: string): FileSpec {
  const header = Buffer.from(TINY_WEBM, "base64").subarray(0, 40);
  return { name, mimeType: "video/webm", buffer: Buffer.concat([header, Buffer.alloc(200, 0x55)]) };
}

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
  if (kind === "paste") return pasteData(editable.page(), editable, { files });
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
      const point = { clientX: rect.left + 10, clientY: rect.top + 10 };
      element.dispatchEvent(new DragEvent("dragover", { ...init, ...point, dataTransfer: data }));
      element.dispatchEvent(new DragEvent("drop", { ...init, ...point, dataTransfer: data }));
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
