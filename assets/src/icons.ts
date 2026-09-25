// Icons from Lucide (https://lucide.dev), ISC licence.
//
// Each icon is the list of the SVG shapes of one Lucide icon (24 × 24,
// stroke only), copied from the lucide-static package. `renderIcon` makes
// the SVG element. The bundle does not import Lucide.

import type { ToolbarCommand } from "./toolbar";

type Shape = readonly [tag: "path" | "line" | "rect" | "circle" | "polyline", attributes: Readonly<Record<string, string>>];
export type Icon = readonly Shape[];

/** Lucide `bold`. */
export const bold: Icon = [
  ["path", { d: "M6 12h9a4 4 0 0 1 0 8H7a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h7a4 4 0 0 1 0 8" }],
];

/** Lucide `italic`. */
export const italic: Icon = [
  ["line", { x1: "19", x2: "10", y1: "4", y2: "4" }],
  ["line", { x1: "14", x2: "5", y1: "20", y2: "20" }],
  ["line", { x1: "15", x2: "9", y1: "4", y2: "20" }],
];

/** Lucide `strikethrough`. */
export const strikethrough: Icon = [
  ["path", { d: "M16 4H9a3 3 0 0 0-2.83 4" }],
  ["path", { d: "M14 12a4 4 0 0 1 0 8H6" }],
  ["line", { x1: "4", x2: "20", y1: "12", y2: "12" }],
];

/** Lucide `code`. */
export const code: Icon = [
  ["path", { d: "m16 18 6-6-6-6" }],
  ["path", { d: "m8 6-6 6 6 6" }],
];

/** Lucide `link`. */
export const link: Icon = [
  ["path", { d: "M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" }],
  ["path", { d: "M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" }],
];

/** Lucide `heading-1`. */
export const heading1: Icon = [
  ["path", { d: "M4 12h8" }],
  ["path", { d: "M4 18V6" }],
  ["path", { d: "M12 18V6" }],
  ["path", { d: "m17 12 3-2v8" }],
];

/** Lucide `heading-2`. */
export const heading2: Icon = [
  ["path", { d: "M4 12h8" }],
  ["path", { d: "M4 18V6" }],
  ["path", { d: "M12 18V6" }],
  ["path", { d: "M21 18h-4c0-4 4-3 4-6 0-1.5-2-2.5-4-1" }],
];

/** Lucide `heading-3`. */
export const heading3: Icon = [
  ["path", { d: "M4 12h8" }],
  ["path", { d: "M4 18V6" }],
  ["path", { d: "M12 18V6" }],
  ["path", { d: "M17.5 10.5c1.7-1 3.5 0 3.5 1.5a2 2 0 0 1-2 2" }],
  ["path", { d: "M17 17.5c2 1.5 4 .3 4-1.5a2 2 0 0 0-2-2" }],
];

/** Lucide `heading-4`. */
export const heading4: Icon = [
  ["path", { d: "M12 18V6" }],
  ["path", { d: "M17 10v3a1 1 0 0 0 1 1h3" }],
  ["path", { d: "M21 10v8" }],
  ["path", { d: "M4 12h8" }],
  ["path", { d: "M4 18V6" }],
];

/** Lucide `text-quote`. */
export const textQuote: Icon = [
  ["path", { d: "M17 5H3" }],
  ["path", { d: "M21 12H8" }],
  ["path", { d: "M21 19H8" }],
  ["path", { d: "M3 12v7" }],
];

/** Lucide `list`. */
export const list: Icon = [
  ["path", { d: "M3 5h.01" }],
  ["path", { d: "M3 12h.01" }],
  ["path", { d: "M3 19h.01" }],
  ["path", { d: "M8 5h13" }],
  ["path", { d: "M8 12h13" }],
  ["path", { d: "M8 19h13" }],
];

/** Lucide `list-ordered`. */
export const listOrdered: Icon = [
  ["path", { d: "M11 5h10" }],
  ["path", { d: "M11 12h10" }],
  ["path", { d: "M11 19h10" }],
  ["path", { d: "M4 4h1v5" }],
  ["path", { d: "M4 9h2" }],
  ["path", { d: "M6.5 20H3.4c0-1 2.6-1.925 2.6-3.5a1.5 1.5 0 0 0-2.6-1.02" }],
];

/** Lucide `list-checks`. */
export const listChecks: Icon = [
  ["path", { d: "M13 5h8" }],
  ["path", { d: "M13 12h8" }],
  ["path", { d: "M13 19h8" }],
  ["path", { d: "m3 17 2 2 4-4" }],
  ["path", { d: "m3 7 2 2 4-4" }],
];

/** Lucide `square-code`. */
export const squareCode: Icon = [
  ["path", { d: "m10 9-3 3 3 3" }],
  ["path", { d: "m14 15 3-3-3-3" }],
  ["rect", { x: "3", y: "3", width: "18", height: "18", rx: "2" }],
];

/** Lucide `minus`. */
export const minus: Icon = [
  ["path", { d: "M5 12h14" }],
];

/** Lucide `paperclip`. */
export const paperclip: Icon = [
  ["path", { d: "m16 6-8.414 8.586a2 2 0 0 0 2.829 2.829l8.414-8.586a4 4 0 1 0-5.657-5.657l-8.379 8.551a6 6 0 1 0 8.485 8.485l8.379-8.551" }],
];

/** Lucide `undo-2`. */
export const undo2: Icon = [
  ["path", { d: "M9 14 4 9l5-5" }],
  ["path", { d: "M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11" }],
];

/** Lucide `redo-2`. */
export const redo2: Icon = [
  ["path", { d: "m15 14 5-5-5-5" }],
  ["path", { d: "M20 9H9.5A5.5 5.5 0 0 0 4 14.5A5.5 5.5 0 0 0 9.5 20H13" }],
];

/** The icon of each toolbar command. */
export const TOOLBAR_ICONS: Readonly<Record<ToolbarCommand, Icon>> = {
  "bold": bold,
  "italic": italic,
  "strikethrough": strikethrough,
  "code": code,
  "link": link,
  "h1": heading1,
  "h2": heading2,
  "h3": heading3,
  "h4": heading4,
  "quote": textQuote,
  "bullet": list,
  "number": listOrdered,
  "check": listChecks,
  "code-block": squareCode,
  "rule": minus,
  "upload": paperclip,
  "undo": undo2,
  "redo": redo2,
};

const SVG = "http://www.w3.org/2000/svg";

/** Makes the SVG element of an icon. It is hidden from assistive technology. */
export function renderIcon(icon: Icon): SVGSVGElement {
  const svg = document.createElementNS(SVG, "svg");
  const attributes: Record<string, string> = {
    class: "kotoba-icon",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    "stroke-width": "2",
    "stroke-linecap": "round",
    "stroke-linejoin": "round",
    "aria-hidden": "true",
    focusable: "false",
  };
  for (const [name, value] of Object.entries(attributes)) svg.setAttribute(name, value);

  for (const [tag, shapeAttributes] of icon) {
    const shape = document.createElementNS(SVG, tag);
    for (const [name, value] of Object.entries(shapeAttributes)) shape.setAttribute(name, value);
    svg.append(shape);
  }
  return svg;
}
