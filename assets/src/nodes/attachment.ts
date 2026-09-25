// The `attachment` node: a file in the document, for example an image.
//
// The JSON keys mirror `Kotoba.Nodes.Attachment`: `key`, `url`, `name`,
// `contentType`, `bytes`, and `width` and `height` for an image.

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
    const { key, url, name, contentType, bytes, width, height } = this.getLatest().__attachment;
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
    return json;
  }

  getAttachment(): AttachmentPayload {
    return { ...this.getLatest().__attachment };
  }

  isImage(): boolean {
    return this.getLatest().__attachment.contentType.startsWith("image/");
  }

  getTextContent(): string {
    return this.getLatest().__attachment.name;
  }

  isInline(): boolean {
    return false;
  }

  className(): string {
    return "kotoba-attachment";
  }

  render(): HTMLElement {
    const { url, name, contentType, bytes, width, height } = this.__attachment;
    const figure = element("figure", "kotoba-attachment-figure");
    const src = safeUrl(url);

    if (contentType.startsWith("image/") && src !== null) {
      const image = element("img", "kotoba-attachment-image");
      image.src = src;
      image.alt = name;
      image.draggable = false;
      image.loading = "lazy";
      if (typeof width === "number") image.width = width;
      if (typeof height === "number") image.height = height;
      figure.append(image);
    } else {
      figure.append(element("span", "kotoba-attachment-icon", fileExtension(name)));
    }

    const caption = element("figcaption", "kotoba-attachment-caption");
    caption.append(element("span", "kotoba-attachment-name", name));
    caption.append(element("span", "kotoba-attachment-size", formatBytes(bytes)));
    figure.append(caption);
    return figure;
  }
}

export function $createAttachmentNode(attachment: AttachmentPayload): AttachmentNode {
  return $applyNodeReplacement(new AttachmentNode(attachment));
}

export function $isAttachmentNode(node: LexicalNode | null | undefined): node is AttachmentNode {
  return node instanceof AttachmentNode;
}

function readAttachment(json: SerializedPartial<SerializedAttachmentNode>): AttachmentPayload {
  return {
    key: String(json.key ?? ""),
    url: String(json.url ?? ""),
    name: String(json.name ?? ""),
    contentType: String(json.contentType ?? "application/octet-stream"),
    bytes: typeof json.bytes === "number" ? json.bytes : 0,
    width: typeof json.width === "number" ? json.width : null,
    height: typeof json.height === "number" ? json.height : null,
  };
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
