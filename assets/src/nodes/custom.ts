// Loads the app's node modules, named by URL in `data-nodes`.
//
// Each module is loaded with `import()`. Every export that is a Lexical node
// class (a function with a static `getType`) is registered. A module can
// also export a `default` function (without `getType`): Kotoba calls it with
// the `lexical` module and registers the class, or the array of classes, it
// returns. Use this form to extend `DecoratorNode` from the same copy of
// Lexical that the editor uses:
//
//     export default ({ DecoratorNode }) =>
//       class PointerNode extends DecoratorNode { static getType() { return "pointer" } ... }
//
// A module that fails to load is logged with its URL; the editor still
// mounts with the built-in nodes.

import * as lexical from "lexical";
import type { Klass, LexicalNode } from "lexical";

export type NodeClass = Klass<LexicalNode>;

export function isNodeClass(value: unknown): value is NodeClass {
  return (
    typeof value === "function" &&
    typeof (value as { getType?: unknown }).getType === "function" &&
    typeof (value as { clone?: unknown }).clone === "function"
  );
}

export async function loadNodes(urls: readonly string[]): Promise<NodeClass[]> {
  const modules = await Promise.all(urls.map(loadModule));
  return modules.flat();
}

async function loadModule(url: string): Promise<NodeClass[]> {
  try {
    const module: Record<string, unknown> = await import(/* webpackIgnore: true */ url);
    const classes = Object.values(module).filter(isNodeClass);

    const factory = module.default;
    if (typeof factory === "function" && !isNodeClass(factory)) {
      const made: unknown = (factory as (api: typeof lexical) => unknown)(lexical);
      for (const value of Array.isArray(made) ? made : [made]) {
        if (isNodeClass(value)) classes.push(value);
      }
    }

    if (classes.length === 0) {
      console.error(`Kotoba: the node module ${url} exports no Lexical node class`);
    }
    return classes;
  } catch (error) {
    console.error(`Kotoba: could not load the node module ${url}`, error);
    return [];
  }
}
