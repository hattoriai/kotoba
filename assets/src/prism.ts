// Keeps the editor's Prism away from the host page.
//
// `prismjs` and its grammars work through the global `Prism`: the core sets
// `globalThis.Prism`, and each grammar extends it when it loads.
// `@lexical/code-prism` keeps a reference to that instance when it loads.
// So this module:
//
//   1. saves the host page's `Prism` (if any) and puts a settings object in
//      its place, with manual mode on, so that the editor's Prism does not
//      highlight the `code[class*=language-]` elements of the page;
//   2. after the editor module has loaded Prism and its grammars,
//      `restoreHostPrism()` puts the host page's `Prism` back.
//
// A page that had no `Prism` keeps the editor's instance as `window.Prism`,
// as a page that loads `prismjs` would. This module must be imported before
// `@lexical/code-prism`.

interface PrismSettings {
  manual?: boolean;
  disableWorkerMessageHandler?: boolean;
}

const scope = globalThis as { Prism?: unknown };
const hadHostPrism = Object.prototype.hasOwnProperty.call(scope, "Prism") && scope.Prism !== undefined;
const hostPrism = scope.Prism;

const settings: PrismSettings = { manual: true, disableWorkerMessageHandler: true };
scope.Prism = settings;

/** Puts the host page's `Prism` back, once the editor's Prism has loaded. */
export function restoreHostPrism(): void {
  if (hadHostPrism) scope.Prism = hostPrism;
}
