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

/** Lucide `underline`. */
export const underline: Icon = [
  ["path", { d: "M6 4v6a6 6 0 0 0 12 0V4" }],
  ["line", { x1: "4", x2: "20", y1: "20", y2: "20" }],
];

/** Lucide `highlighter`. */
export const highlighter: Icon = [
  ["path", { d: "m9 11-6 6v3h9l3-3" }],
  ["path", { d: "m22 12-4.6 4.6a2 2 0 0 1-2.8 0l-5.2-5.2a2 2 0 0 1 0-2.8L14 4" }],
];

/** Lucide `subscript`. */
export const subscript: Icon = [
  ["path", { d: "m4 5 8 8" }],
  ["path", { d: "m12 5-8 8" }],
  [
    "path",
    { d: "M20 19h-4c0-1.5.44-2 1.5-2.5S20 15.33 20 14c0-.47-.17-.93-.48-1.29a2.11 2.11 0 0 0-2.62-.44c-.42.24-.74.62-.9 1.07" },
  ],
];

/** Lucide `superscript`. */
export const superscript: Icon = [
  ["path", { d: "m4 19 8-8" }],
  ["path", { d: "m12 19-8-8" }],
  [
    "path",
    { d: "M20 12h-4c0-1.5.442-2 1.5-2.5S20 8.334 20 7.002c0-.472-.17-.93-.484-1.29a2.105 2.105 0 0 0-2.617-.436c-.42.239-.738.614-.899 1.06" },
  ],
];

/** Lucide `sparkles`. */
export const sparkles: Icon = [
  [
    "path",
    {
      d: "M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z",
    },
  ],
  ["path", { d: "M20 2v4" }],
  ["path", { d: "M22 4h-4" }],
  ["circle", { cx: "4", cy: "20", r: "2" }],
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

/** Lucide `table`. */
export const table: Icon = [
  ["path", { d: "M12 3v18" }],
  ["rect", { width: "18", height: "18", x: "3", y: "3", rx: "2" }],
  ["path", { d: "M3 9h18" }],
  ["path", { d: "M3 15h18" }],
];

/** Lucide `between-horizontal-start`. */
export const betweenHorizontalStart: Icon = [
  ["rect", { width: "13", height: "7", x: "8", y: "3", rx: "1" }],
  ["path", { d: "m2 9 3 3-3 3" }],
  ["rect", { width: "13", height: "7", x: "8", y: "14", rx: "1" }],
];

/** Lucide `between-horizontal-end`. */
export const betweenHorizontalEnd: Icon = [
  ["rect", { width: "13", height: "7", x: "3", y: "3", rx: "1" }],
  ["path", { d: "m22 15-3-3 3-3" }],
  ["rect", { width: "13", height: "7", x: "3", y: "14", rx: "1" }],
];

/** Lucide `between-vertical-start`. */
export const betweenVerticalStart: Icon = [
  ["rect", { width: "7", height: "13", x: "3", y: "8", rx: "1" }],
  ["path", { d: "m15 2-3 3-3-3" }],
  ["rect", { width: "7", height: "13", x: "14", y: "8", rx: "1" }],
];

/** Lucide `between-vertical-end`. */
export const betweenVerticalEnd: Icon = [
  ["rect", { width: "7", height: "13", x: "3", y: "3", rx: "1" }],
  ["path", { d: "m9 22 3-3 3 3" }],
  ["rect", { width: "7", height: "13", x: "14", y: "3", rx: "1" }],
];

/** Lucide `panel-top`. */
export const panelTop: Icon = [
  ["rect", { width: "18", height: "18", x: "3", y: "3", rx: "2" }],
  ["path", { d: "M3 9h18" }],
];

/** Lucide `panel-left`. */
export const panelLeft: Icon = [
  ["rect", { width: "18", height: "18", x: "3", y: "3", rx: "2" }],
  ["path", { d: "M9 3v18" }],
];

/** Lucide `table-rows-split`. */
export const tableRowsSplit: Icon = [
  ["path", { d: "M14 10h2" }],
  ["path", { d: "M15 22v-8" }],
  ["path", { d: "M15 2v4" }],
  ["path", { d: "M2 10h2" }],
  ["path", { d: "M20 10h2" }],
  ["path", { d: "M3 19h18" }],
  ["path", { d: "M3 22v-6a2 2 135 0 1 2-2h14a2 2 45 0 1 2 2v6" }],
  ["path", { d: "M3 2v2a2 2 45 0 0 2 2h14a2 2 135 0 0 2-2V2" }],
  ["path", { d: "M8 10h2" }],
  ["path", { d: "M9 22v-8" }],
  ["path", { d: "M9 2v4" }],
];

/** Lucide `table-columns-split`. */
export const tableColumnsSplit: Icon = [
  ["path", { d: "M14 14v2" }],
  ["path", { d: "M14 20v2" }],
  ["path", { d: "M14 2v2" }],
  ["path", { d: "M14 8v2" }],
  ["path", { d: "M2 15h8" }],
  ["path", { d: "M2 3h6a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H2" }],
  ["path", { d: "M2 9h8" }],
  ["path", { d: "M22 15h-4" }],
  ["path", { d: "M22 3h-2a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h2" }],
  ["path", { d: "M22 9h-4" }],
  ["path", { d: "M5 3v18" }],
];

/** Lucide `grid-2x2-x`. */
export const grid2x2X: Icon = [
  ["path", { d: "M12 3v17a1 1 0 0 1-1 1H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v6a1 1 0 0 1-1 1H3" }],
  ["path", { d: "m16.5 16.5 5 5" }],
  ["path", { d: "m16.5 21.5 5-5" }],
];

/** Lucide `images`. */
export const images: Icon = [
  ["path", { d: "m22 11-1.296-1.296a2.4 2.4 0 0 0-3.408 0L11 16" }],
  ["path", { d: "M4 8a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2" }],
  ["circle", { cx: "13", cy: "7", r: "1", fill: "currentColor" }],
  ["rect", { x: "8", y: "2", width: "14", height: "14", rx: "2" }],
];

/** Lucide `arrow-left`. */
export const arrowLeft: Icon = [
  ["path", { d: "m12 19-7-7 7-7" }],
  ["path", { d: "M19 12H5" }],
];

/** Lucide `arrow-right`. */
export const arrowRight: Icon = [
  ["path", { d: "M5 12h14" }],
  ["path", { d: "m12 5 7 7-7 7" }],
];

/** The icon of each toolbar command that is a button (`code-language` is a select). */
export const TOOLBAR_ICONS: Readonly<Record<Exclude<ToolbarCommand, "code-language">, Icon>> = {
  "bold": bold,
  "italic": italic,
  "underline": underline,
  "strikethrough": strikethrough,
  "highlight": highlighter,
  "code": code,
  "subscript": subscript,
  "superscript": superscript,
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
  "table": table,
  "upload": paperclip,
  "assist": sparkles,
  "gallery": images,
  "image-previous": arrowLeft,
  "image-next": arrowRight,
  "table-row-before": betweenHorizontalStart,
  "table-row-after": betweenHorizontalEnd,
  "table-column-before": betweenVerticalStart,
  "table-column-after": betweenVerticalEnd,
  "table-header-row": panelTop,
  "table-header-column": panelLeft,
  "table-delete-row": tableRowsSplit,
  "table-delete-column": tableColumnsSplit,
  "table-delete": grid2x2X,
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
