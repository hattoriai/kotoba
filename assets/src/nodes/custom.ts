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
// A class must extend the editor's copy of Lexical; any other class is
// logged and skipped. A module that fails to load is logged with its URL.
// In every case the editor still mounts, with the built-in nodes.

import * as lexical from "lexical";
import type { Klass, LexicalNode } from "lexical";

export type NodeClass = Klass<LexicalNode>;

function hasNodeStatics(value: unknown): value is NodeClass {
  return (
    typeof value === "function" &&
    typeof (value as { getType?: unknown }).getType === "function" &&
    typeof (value as { clone?: unknown }).clone === "function"
  );
}

// The editor's `LexicalNode` class. The package exports it only as a type,
// so it is read from the prototype chain of `DecoratorNode`.
const LexicalNodeBase = Object.getPrototypeOf(lexical.DecoratorNode) as abstract new (
  ...args: never[]
) => object;

/** Returns `true` for a node class that extends the editor's copy of Lexical. */
export function isNodeClass(value: unknown): value is NodeClass {
  return hasNodeStatics(value) && value.prototype instanceof LexicalNodeBase;
}

// Keeps the node classes of the editor's Lexical. A class from another copy
// of Lexical (a module that bundles its own) would stop the editor from
// mounting, so it is logged and skipped.
function keepNodeClasses(url: string, entries: [string, unknown][]): NodeClass[] {
  const classes: NodeClass[] = [];
  for (const [name, value] of entries) {
    if (isNodeClass(value)) {
      classes.push(value);
    } else if (hasNodeStatics(value)) {
      console.error(
        `Kotoba: ${url} exports ${name}, which does not extend the editor's Lexical; use the default factory form`,
      );
    }
  }
  return classes;
}

export async function loadNodes(urls: readonly string[]): Promise<NodeClass[]> {
  const modules = await Promise.all(urls.map(loadModule));
  return modules.flat();
}

async function loadModule(url: string): Promise<NodeClass[]> {
  try {
    const module: Record<string, unknown> = await import(/* webpackIgnore: true */ /* @vite-ignore */ url);
    const factory = module.default;
    const exported = Object.entries(module).filter(([name]) => name !== "default" || hasNodeStatics(factory));
    const classes = keepNodeClasses(url, exported);

    if (typeof factory === "function" && !hasNodeStatics(factory)) {
      const made: unknown = (factory as (api: typeof lexical) => unknown)(lexical);
      const list = Array.isArray(made) ? made : [made];
      classes.push(...keepNodeClasses(url, list.map((value, index): [string, unknown] => [`default()[${index}]`, value])));
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
