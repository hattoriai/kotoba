// Shared behaviour of the Kotoba decorator nodes, and the code that puts a
// decorator's HTMLElement into the editor.
//
// In vanilla Lexical, `decorate()` returns a value and the host puts it on
// the page. Every Kotoba decorator (and every app node) returns an
// HTMLElement; `registerDecorators` mounts it in the node's DOM element.

import {
  $createNodeSelection,
  $getNearestNodeFromDOMNode,
  $getSelection,
  $isDecoratorNode,
  $isNodeSelection,
  $setSelection,
  CLICK_COMMAND,
  COMMAND_PRIORITY_LOW,
  DecoratorNode,
  isDOMNode,
  mergeRegister,
  type EditorConfig,
  type LexicalEditor,
  type NodeKey,
} from "lexical";

export const SELECTED_CLASS = "kotoba-selected";

/**
 * The base class of the built-in decorator nodes. A subclass sets
 * `className` and implements `render()`, which returns the inert content.
 */
export abstract class KotobaDecoratorNode extends DecoratorNode<HTMLElement> {
  abstract className(): string;
  abstract render(): HTMLElement;

  createDOM(_config: EditorConfig): HTMLElement {
    const element = document.createElement(this.isInline() ? "span" : "div");
    element.className = this.className();
    element.contentEditable = "false";
    return element;
  }

  updateDOM(): boolean {
    return false;
  }

  decorate(_editor: LexicalEditor, _config: EditorConfig): HTMLElement {
    return this.render();
  }

  isKeyboardSelectable(): boolean {
    return true;
  }
}

/** Creates an element with a class and text. */
export function element<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className: string,
  text?: string,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

/**
 * Mounts decorations in the editor, selects a decorator node on click, and
 * marks the selected decorator nodes with the `kotoba-selected` class.
 */
export function registerDecorators(editor: LexicalEditor): () => void {
  let selected = new Set<NodeKey>();

  return mergeRegister(
    editor.registerDecoratorListener<unknown>((decorators) => {
      for (const [key, decoration] of Object.entries(decorators)) {
        const host = editor.getElementByKey(key);
        if (host === null || !(decoration instanceof HTMLElement)) continue;
        if (host.firstChild !== decoration || host.childNodes.length !== 1) {
          host.replaceChildren(decoration);
        }
      }
    }),

    editor.registerCommand(
      CLICK_COMMAND,
      (event: MouseEvent) => {
        if (!isDOMNode(event.target)) return false;
        const node = $getNearestNodeFromDOMNode(event.target);
        if (!$isDecoratorNode(node)) return false;

        const current = $getSelection();
        const selection =
          event.shiftKey && $isNodeSelection(current) ? current : $createNodeSelection();
        selection.add(node.getKey());
        $setSelection(selection);
        return true;
      },
      COMMAND_PRIORITY_LOW,
    ),

    editor.registerUpdateListener(({ editorState }) => {
      const next = editorState.read(() => {
        const selection = $getSelection();
        return new Set<NodeKey>(
          $isNodeSelection(selection) ? selection.getNodes().map((node) => node.getKey()) : [],
        );
      });

      for (const key of selected) {
        if (!next.has(key)) editor.getElementByKey(key)?.classList.remove(SELECTED_CLASS);
      }
      for (const key of next) editor.getElementByKey(key)?.classList.add(SELECTED_CLASS);
      selected = next;
    }),
  );
}
