// The caption field: a line under the attachment that is selected alone, to
// write its caption on (the `caption` of the attachment node, its `alt` and
// `figcaption` in the saved page).
//
// It shows while the attachment is selected and the focus is in the editor,
// as the link card shows under a link. A click puts the caret in it, and
// Alt+F10 moves the focus to it. Enter keeps the caption and gives the focus
// back to the editor, with the attachment selected; leaving the field keeps
// it too. Escape in the field gives the focus back without a change, and
// Escape in the editor hides the field until the selection changes or the
// person clicks in the editor. Keeping
// a caption is one change of the document: Cmd/Ctrl+Z takes it back, and a
// shared editor sends it to the others.

import {
  $createNodeSelection,
  $getNodeByKey,
  $setSelection,
  COMMAND_PRIORITY_NORMAL,
  KEY_DOWN_COMMAND,
  mergeRegister,
  type LexicalEditor,
  type NodeKey,
} from "lexical";

import { $selectedAttachment } from "./gallery";
import { $isAttachmentNode, cleanCaption } from "./nodes/attachment";
import { BUSY, placeOver, type Floating } from "./selection_menu";

interface CaptionOptions {
  /** The positioned element that holds the field (the editor's surface). */
  host: HTMLElement;
  /** The hook element: the focus in it keeps the field. */
  root: HTMLElement;
  idPrefix: string;
  announce(message: string): void;
}

interface Target {
  key: NodeKey;
  name: string;
  caption: string | null;
}

/** The longest caption, as the server's limit of a field. */
const MAX_LENGTH = 2048;

export function attachCaptionField(editor: LexicalEditor, options: CaptionOptions): Floating {
  const { host, root } = options;

  // A div, not a form: the editor is usually inside the app's form.
  const field = document.createElement("div");
  field.className = "kotoba-caption-field";
  field.hidden = true;
  field.setAttribute("role", "group");
  field.setAttribute("aria-label", "Caption");

  const input = document.createElement("input");
  input.id = `${options.idPrefix}-caption`;
  input.type = "text";
  input.className = "kotoba-caption-input";
  input.placeholder = "Add a caption";
  input.maxLength = MAX_LENGTH;
  input.autocomplete = "off";
  input.setAttribute("enterkeyhint", "done");
  field.append(input);
  host.append(field);

  // The selected attachment, and the one the field writes the caption of
  // while it has the focus (the editor's selection may change meanwhile).
  let target: Target | null = null;
  let editing: Target | null = null;
  let dismissed: NodeKey | null = null;
  let frame = 0;

  const $read = (): Target | null => {
    const node = $selectedAttachment();
    if (node === null) return null;
    return { key: node.getKey(), name: node.getAttachment().name, caption: node.getCaption() };
  };

  const focused = (): boolean => document.activeElement === input;

  const update = (): void => {
    frame = 0;
    const current = editing ?? target;
    const active = document.activeElement;
    const show =
      current !== null &&
      (focused() ||
        (dismissed !== current.key &&
          editor.isEditable() &&
          active !== null &&
          root.contains(active) &&
          host.querySelector(BUSY) === null));
    const element = show && current !== null ? editor.getElementByKey(current.key) : null;
    if (!show || current === null || element === null) {
      field.hidden = true;
      return;
    }

    input.setAttribute("aria-label", `Caption of ${current.name}`);
    // The person's words while they write; else the node's caption.
    if (!focused()) input.value = current.caption ?? "";
    field.hidden = false;
    // Under the attachment's own caption, where the field's caption shows.
    const figure = element.querySelector(".kotoba-attachment-figure") ?? element;
    placeOver(field, host, figure.getBoundingClientRect(), "bottom");
  };

  const schedule = (): void => {
    if (frame === 0) frame = requestAnimationFrame(update);
  };

  // Keeps the caption in the field on the node. One update: one undo step.
  const commit = (): void => {
    const current = editing;
    if (current === null || !editor.isEditable()) return;
    const caption = cleanCaption(input.value);
    if (caption === current.caption) return;
    let kept = false;
    editor.update(
      () => {
        const node = $getNodeByKey(current.key);
        if (!$isAttachmentNode(node) || !node.isAttached()) return;
        node.setCaption(caption);
        kept = true;
      },
      { discrete: true },
    );
    if (!kept) return;
    current.caption = caption;
    options.announce(caption === null ? "Caption removed" : "Caption saved");
  };

  // The focus back to the editor, with the attachment selected.
  const back = (): void => {
    const key = editing?.key ?? target?.key;
    editing = null;
    // Not editor.focus(): it would put the caret where the DOM selection is.
    editor.getRootElement()?.focus({ preventScroll: true });
    if (key === undefined) return;
    editor.update(() => {
      const node = $getNodeByKey(key);
      if (!$isAttachmentNode(node) || !node.isAttached()) return;
      const selection = $createNodeSelection();
      selection.add(key);
      $setSelection(selection);
    });
  };

  const onFocusIn = (): void => {
    if (editing === null && target !== null) editing = { ...target };
  };

  const onKeyDown = (event: KeyboardEvent): void => {
    if (event.key === "Enter" && !event.isComposing) {
      // Enter in the input would otherwise submit the app's form.
      event.preventDefault();
      event.stopPropagation();
      commit();
      back();
    } else if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      input.value = editing?.caption ?? "";
      back();
    }
  };

  // The input has no name, but its events would still reach the app's form
  // (a phx-change with an empty target).
  const onInput = (event: Event): void => event.stopPropagation();

  const onFieldFocusOut = (event: FocusEvent): void => {
    if (editing === null) return;
    commit();
    editing = null;
    if (!(event.relatedTarget instanceof Node && root.contains(event.relatedTarget))) field.hidden = true;
    schedule();
  };

  const onRootFocusOut = (event: FocusEvent): void => {
    if (event.relatedTarget instanceof Node && root.contains(event.relatedTarget)) return;
    if (!focused()) field.hidden = true;
  };

  // A click on the attachment shows the field again after Escape.
  const onPointerDown = (event: PointerEvent): void => {
    if (event.target instanceof Node && editor.getRootElement()?.contains(event.target)) {
      dismissed = null;
      schedule();
    }
  };

  const onViewportChange = (): void => {
    if (!field.hidden) schedule();
  };

  input.addEventListener("focusin", onFocusIn);
  input.addEventListener("keydown", onKeyDown);
  input.addEventListener("input", onInput);
  input.addEventListener("change", onInput);
  input.addEventListener("focusout", onFieldFocusOut);
  root.addEventListener("focusin", schedule);
  root.addEventListener("focusout", onRootFocusOut);
  root.addEventListener("pointerdown", onPointerDown);
  window.addEventListener("scroll", onViewportChange, true);
  window.addEventListener("resize", onViewportChange);

  const unregister = mergeRegister(
    editor.registerUpdateListener(({ editorState }) => {
      const next = editorState.read($read);
      if (next?.key !== target?.key) dismissed = null;
      target = next;
      // A caption changed elsewhere (undo, a collaborator) while the field
      // is not in use shows in it.
      schedule();
    }),
    editor.registerEditableListener((editable) => {
      input.disabled = !editable;
      schedule();
    }),
    editor.registerCommand(
      KEY_DOWN_COMMAND,
      (event: KeyboardEvent) => {
        if (field.hidden || target === null) return false;
        if (event.key === "Escape" && !event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey) {
          dismissed = target.key;
          field.hidden = true;
          return true;
        }
        if (event.altKey && event.key === "F10" && !event.ctrlKey && !event.metaKey && !event.shiftKey) {
          event.preventDefault();
          input.focus();
          input.select();
          return true;
        }
        return false;
      },
      COMMAND_PRIORITY_NORMAL,
    ),
  );

  return {
    dispose() {
      unregister();
      if (frame !== 0) cancelAnimationFrame(frame);
      input.removeEventListener("focusin", onFocusIn);
      input.removeEventListener("keydown", onKeyDown);
      input.removeEventListener("input", onInput);
      input.removeEventListener("change", onInput);
      input.removeEventListener("focusout", onFieldFocusOut);
      root.removeEventListener("focusin", schedule);
      root.removeEventListener("focusout", onRootFocusOut);
      root.removeEventListener("pointerdown", onPointerDown);
      window.removeEventListener("scroll", onViewportChange, true);
      window.removeEventListener("resize", onViewportChange);
      field.remove();
    },
  };
}
