// Prism highlights every `code[class*=language-]` on the page when it loads,
// unless it is in manual mode. The editor highlights only its own code blocks,
// so this module turns manual mode on before Prism loads. It must be
// imported before `@lexical/code-prism`.

interface PrismSettings {
  manual?: boolean;
  disableWorkerMessageHandler?: boolean;
}

const scope = globalThis as { Prism?: PrismSettings };
scope.Prism = scope.Prism ?? {};
scope.Prism.manual = true;
scope.Prism.disableWorkerMessageHandler = true;

export {};
