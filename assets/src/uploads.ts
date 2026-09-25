// The upload bridge. The toolbar's attach button opens a hidden file input
// that the hook owns; a file dropped or pasted in the editor comes through
// Lexical's DRAG_DROP_PASTE command. In both cases the hook puts an upload
// marker at the caret for each file and hands the files to the LiveView file
// input (`data-upload`) with LiveView's `track-uploads` event. When the
// server has stored a file, it pushes `insert_node` with an attachment node,
// which takes the place of the oldest marker.

import { DRAG_DROP_PASTE } from "@lexical/rich-text";
import {
  $createParagraphNode,
  $getNodeByKey,
  $getRoot,
  $getSelection,
  $insertNodes,
  $isRangeSelection,
  COMMAND_PRIORITY_LOW,
  mergeRegister,
  type LexicalEditor,
  type LexicalNode,
  type NodeKey,
} from "lexical";

import { $createUploadMarkerNode, $isUploadMarkerNode } from "./nodes/internal";

export interface Uploads {
  enabled: boolean;
  open(): void;
  /** Puts a node in place of the oldest upload marker, or at the selection. */
  $insert(node: LexicalNode): void;
  /** Forgets the upload markers (for example after `set_content`). */
  reset(): void;
  dispose(): void;
}

interface UploadOptions {
  host: HTMLElement;
  /** The LiveView file input, or `null` when the editor takes no uploads. */
  target: HTMLInputElement | null;
  announce(message: string): void;
}

/** Inserts a node at the selection, or at the end of the document. */
export function $insertAtSelection(node: LexicalNode): void {
  const selection = $getSelection();
  if ($isRangeSelection(selection)) {
    $insertNodes([node]);
    return;
  }
  const paragraph = $createParagraphNode();
  $getRoot().append(paragraph);
  paragraph.select();
  $insertNodes([node]);
}

export function createUploads(editor: LexicalEditor, options: UploadOptions): Uploads {
  const { target } = options;
  let markers: NodeKey[] = [];

  const picker = document.createElement("input");
  picker.type = "file";
  picker.hidden = true;
  picker.tabIndex = -1;
  picker.setAttribute("aria-hidden", "true");
  picker.className = "kotoba-file-picker";

  const syncPicker = (): void => {
    if (target === null) return;
    picker.multiple = target.multiple;
    if (target.accept) picker.accept = target.accept;
    else picker.removeAttribute("accept");
  };

  const handOff = (files: File[]): void => {
    if (target === null || files.length === 0) return;

    editor.update(
      () => {
        for (const file of files) {
          const marker = $createUploadMarkerNode(file.name);
          $insertAtSelection(marker);
          markers.push(marker.getKey());
        }
      },
      { tag: "history-merge" },
    );

    target.dispatchEvent(new CustomEvent("track-uploads", { bubbles: true, detail: { files } }));
    options.announce(files.length === 1 ? `Uploading ${files[0]?.name ?? "a file"}` : `Uploading ${files.length} files`);
  };

  // The picker's events must not reach the app's form: LiveView would push
  // a form change with an empty target.
  const onInput = (event: Event): void => event.stopPropagation();

  const onChange = (event: Event): void => {
    event.stopPropagation();
    const files = Array.from(picker.files ?? []);
    picker.value = "";
    handOff(target?.multiple ? files : files.slice(0, 1));
  };

  picker.addEventListener("change", onChange);
  picker.addEventListener("input", onInput);
  if (target !== null) options.host.append(picker);

  const unregister = mergeRegister(
    editor.registerCommand(
      DRAG_DROP_PASTE,
      (files: File[]) => {
        if (target === null || !editor.isEditable()) return false;
        handOff(target.multiple ? files : files.slice(0, 1));
        return true;
      },
      COMMAND_PRIORITY_LOW,
    ),
  );

  return {
    enabled: target !== null,
    open() {
      if (target === null || !editor.isEditable()) return;
      syncPicker();
      picker.click();
    },
    $insert(node: LexicalNode) {
      while (markers.length > 0) {
        const key = markers.shift() as NodeKey;
        const marker = $getNodeByKey(key);
        if ($isUploadMarkerNode(marker) && marker.isAttached()) {
          if (node.isInline()) {
            marker.replace(node);
          } else {
            marker.selectPrevious();
            marker.remove();
            $insertNodes([node]);
          }
          return;
        }
      }
      $insertAtSelection(node);
    },
    reset() {
      markers = [];
    },
    dispose() {
      unregister();
      picker.removeEventListener("change", onChange);
      picker.removeEventListener("input", onInput);
      picker.remove();
    },
  };
}
