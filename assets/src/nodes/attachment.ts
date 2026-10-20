// The `attachment` node: a file in the document, for example an image.
//
// The JSON keys mirror `Kotoba.Nodes.Attachment`: `key`, `url`, `name`,
// `contentType`, `bytes`, `width` and `height` for an image, `preview` (an
// image of a PDF's first page, a video's poster frame), and `caption`, what
// the person wrote under it (see caption.ts). An image's caption is its
// `alt`; with none, its file name is.
//
// In the editor, an image shows as an image, a PDF in the browser's PDF
// viewer (or its preview image), and a video as a player with controls,
// no autoplay, that loads only its metadata. The viewer and the player are
// out of the tab order: the person selects the attachment, and plays or
// reads it in the saved page. A video that does not load shows as a file.

import {
  $applyNodeReplacement,
  type LexicalNode,
  type NodeKey,
  type SerializedLexicalNode,
  type SerializedPartial,
  type Spread,
} from "lexical";

import { KotobaDecoratorNode, element } from "./decorator";

export interface AttachmentPayload {
  key: string;
  url: string;
  name: string;
  contentType: string;
  bytes: number;
  width?: number | null;
  height?: number | null;
  preview?: string | null;
  caption?: string | null;
}

export type SerializedAttachmentNode = Spread<AttachmentPayload, SerializedLexicalNode>;

export class AttachmentNode extends KotobaDecoratorNode {
  __attachment: AttachmentPayload;

  static getType(): string {
    return "attachment";
  }

  static clone(node: AttachmentNode): AttachmentNode {
    return new AttachmentNode(node.__attachment, node.__key);
  }

  static importJSON(json: SerializedPartial<SerializedAttachmentNode>): AttachmentNode {
    return $createAttachmentNode(readAttachment(json));
  }

  constructor(attachment: AttachmentPayload, key?: NodeKey) {
    super(key);
    this.__attachment = { ...attachment };
  }

  exportJSON(): SerializedAttachmentNode {
    const { key, url, name, contentType, bytes, width, height, preview, caption } = this.getLatest().__attachment;
    const json: SerializedAttachmentNode = {
      type: "attachment",
      version: 1,
      key,
      url,
      name,
      contentType,
      bytes,
    };
    if (typeof width === "number") json.width = width;
    if (typeof height === "number") json.height = height;
    if (typeof preview === "string") json.preview = preview;
    if (typeof caption === "string" && caption.trim() !== "") json.caption = caption;
    return json;
  }

  getAttachment(): AttachmentPayload {
    return { ...this.getLatest().__attachment };
  }

  /** The caption, or `null` when it has none. */
  getCaption(): string | null {
    return captionOf(this.getLatest().__attachment);
  }

  /** Sets the caption; an empty one (or `null`) removes it. */
  setCaption(caption: string | null): this {
    const writable = this.getWritable();
    writable.__attachment = { ...writable.__attachment, caption: cleanCaption(caption) };
    return writable;
  }

  isImage(): boolean {
    return this.getLatest().__attachment.contentType.startsWith("image/");
  }

  getTextContent(): string {
    const attachment = this.getLatest().__attachment;
    return captionOf(attachment) ?? attachment.name;
  }

  isInline(): boolean {
    return false;
  }

  className(): string {
    const { contentType } = this.__attachment;
    if (contentType === "application/pdf") return "kotoba-attachment kotoba-attachment-pdf";
    if (VIDEO_TYPES.has(contentType)) return "kotoba-attachment kotoba-attachment-video";
    return "kotoba-attachment";
  }

  render(): HTMLElement {
    const { url, name, contentType, bytes, width, height, preview } = this.__attachment;
    const caption = captionOf(this.__attachment);
    // What the image, the viewer and the player are called.
    const label = caption ?? name;
    const figure = element("figure", "kotoba-attachment-figure");
    const src = safeUrl(url);
    const poster = typeof preview === "string" ? safeUrl(preview) : null;
    const icon = () => element("span", "kotoba-attachment-icon", fileExtension(name));

    if (contentType.startsWith("image/") && src !== null) {
      const image = element("img", "kotoba-attachment-image");
      image.src = src;
      image.alt = label;
      image.draggable = false;
      image.loading = "lazy";
      if (typeof width === "number") image.width = width;
      if (typeof height === "number") image.height = height;
      figure.append(image);
    } else if (contentType === "application/pdf" && src !== null && poster !== null) {
      const image = element("img", "kotoba-attachment-preview");
      image.src = poster;
      image.alt = `Preview of ${label}`;
      image.draggable = false;
      image.loading = "lazy";
      figure.append(image);
    } else if (contentType === "application/pdf" && src !== null) {
      // The browser's PDF viewer; with none, the object shows its content.
      const object = element("object", "kotoba-attachment-viewer");
      object.data = src;
      object.type = "application/pdf";
      object.tabIndex = -1;
      object.setAttribute("aria-label", label);
      object.append(icon());
      figure.append(object);
    } else if (VIDEO_TYPES.has(contentType) && src !== null) {
      const video = element("video", "kotoba-attachment-player");
      video.src = src;
      video.controls = true;
      video.preload = "metadata";
      video.playsInline = true;
      video.tabIndex = -1;
      video.setAttribute("aria-label", label);
      if (poster !== null) video.poster = poster;
      // A video that does not load (a format the browser cannot play, a
      // missing file) shows as a file.
      video.addEventListener(
        "error",
        () => {
          figure.classList.add("kotoba-attachment-failed");
          video.replaceWith(icon());
        },
        { once: true },
      );
      figure.append(video);
    } else {
      figure.append(icon());
    }

    const figcaption = element("figcaption", "kotoba-attachment-caption");
    if (caption !== null) {
      figcaption.classList.add("kotoba-attachment-captioned");
      figcaption.append(element("span", "kotoba-attachment-caption-text", caption));
    }
    figcaption.append(element("span", "kotoba-attachment-name", name));
    figcaption.append(element("span", "kotoba-attachment-size", formatBytes(bytes)));
    figure.append(figcaption);
    return figure;
  }
}

export function $createAttachmentNode(attachment: AttachmentPayload): AttachmentNode {
  return $applyNodeReplacement(new AttachmentNode(attachment));
}

export function $isAttachmentNode(node: LexicalNode | null | undefined): node is AttachmentNode {
  return node instanceof AttachmentNode;
}

const VIDEO_TYPES = new Set(["video/mp4", "video/webm"]);

function readAttachment(json: SerializedPartial<SerializedAttachmentNode>): AttachmentPayload {
  return {
    key: String(json.key ?? ""),
    url: String(json.url ?? ""),
    name: String(json.name ?? ""),
    contentType: String(json.contentType ?? "application/octet-stream"),
    bytes: typeof json.bytes === "number" ? json.bytes : 0,
    width: typeof json.width === "number" ? json.width : null,
    height: typeof json.height === "number" ? json.height : null,
    preview: typeof json.preview === "string" ? json.preview : null,
    caption: cleanCaption(typeof json.caption === "string" ? json.caption : null),
  };
}

function captionOf(attachment: AttachmentPayload): string | null {
  return cleanCaption(attachment.caption ?? null);
}

// A caption is one line, with no control character (the server refuses a
// node with one); a blank one is none.
export function cleanCaption(caption: string | null): string | null {
  if (caption === null) return null;
  const line = caption.replace(/[\u0000-\u001F\u007F-\u009F]+/g, " ").replace(/\s+/g, " ").trim();
  return line === "" ? null : line;
}

// The editor shows an image only from an http(s) URL or a path on the site.
function safeUrl(url: string): string | null {
  if (url.startsWith("/") && !url.startsWith("//")) return url;
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" || parsed.protocol === "http:" ? parsed.href : null;
  } catch {
    return null;
  }
}

function fileExtension(name: string): string {
  const dot = name.lastIndexOf(".");
  return dot > 0 && dot < name.length - 1 ? name.slice(dot + 1, dot + 5).toUpperCase() : "FILE";
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB"];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value < 10 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`;
}
