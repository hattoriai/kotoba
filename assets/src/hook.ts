// The `Kotoba` LiveView hook.
//
// Register it with the LiveSocket:
//
//     import { Kotoba } from "kotoba"
//     const liveSocket = new LiveSocket("/live", Socket, { hooks: { Kotoba } })
//
// The hook element (with `phx-hook="Kotoba"`, an `id` and
// `phx-update="ignore"`) has these data attributes:
//
//   * `data-input` - the id of the hidden input that holds the document.
//   * `data-readonly` - present (and not "false") for a read-only editor.
//   * `data-placeholder` - the text to show when the editor is empty.
//   * `data-nodes` - comma-separated URLs of app node modules.
//   * `data-prompts` - JSON: trigger character → prompt name.
//   * `data-upload` - the id of the LiveView file input.
//   * `data-debounce` - milliseconds between `kotoba:change` pushes (300).
//
// The hook pushes (every message has `v: 1`):
//
//   * `kotoba:change` `{v, doc}` - the document envelope, debounced.
//   * `kotoba:prompt` `{v, prompt, query}` - a prompt query.
//
// It handles these server events (a payload with an `id` other than the
// hook element's id is for another editor, and is ignored):
//
//   * `set_content` `{doc}` - replaces the document.
//   * `insert_node` `{node}` - inserts a node (in place of the oldest upload
//     marker, or at the selection).
//   * `set_readonly` `{readonly}`
//   * `focus` `{}`
//   * `kotoba:prompt_results` `{prompt, items: [{id, label, hint?}]}`

import {
  $getRoot,
  $isParagraphNode,
  $parseSerializedNode,
  BLUR_COMMAND,
  CLEAR_HISTORY_COMMAND,
  COMMAND_PRIORITY_LOW,
  type EditorState,
  type LexicalEditor,
  type SerializedEditorState,
  type SerializedLexicalNode,
} from "lexical";

import { createKotobaEditor, registerPlugins, registeredTypes } from "./editor";
import { createLinkForm, type LinkForm } from "./link";
import { loadNodes } from "./nodes/custom";
import { createPrompts, parseTriggers, type Prompts } from "./prompts";
import {
  PROTOCOL_VERSION,
  isObject,
  prepareRoot,
  readRoot,
  toEnvelope,
  type DocumentEnvelope,
  type JSONNode,
} from "./protocol";
import { createToolbar, type Toolbar } from "./toolbar";
import { createUploads, type Uploads } from "./uploads";

/**
 * The part of a LiveView hook that Kotoba uses. LiveView calls the hook's
 * callbacks with `this` bound to an object with these members.
 */
export interface LiveViewHook {
  el: HTMLElement;
  pushEvent(event: string, payload: object): unknown;
  pushEventTo(target: string | HTMLElement, event: string, payload: object): unknown;
  handleEvent(event: string, callback: (payload: unknown) => void): unknown;
  removeHandleEvent(ref: unknown): void;
}

interface KotobaHook extends LiveViewHook {
  kotoba?: Instance;
}

export interface Config {
  input: HTMLInputElement | null;
  readonly: boolean;
  placeholder: string;
  nodes: string[];
  prompts: Map<string, string>;
  upload: HTMLInputElement | null;
  debounce: number;
}

/** Reads the hook's configuration from the data attributes of its element. */
export function readConfig(el: HTMLElement): Config {
  const data = el.dataset;
  const debounce = Number.parseInt(data.debounce ?? "", 10);

  return {
    input: inputById(data.input),
    readonly: data.readonly !== undefined && data.readonly !== "false",
    placeholder: data.placeholder ?? "",
    nodes: (data.nodes ?? "")
      .split(",")
      .map((url) => url.trim())
      .filter((url) => url !== ""),
    prompts: parseTriggers(data.prompts),
    upload: inputById(data.upload),
    debounce: Number.isFinite(debounce) && debounce >= 0 ? debounce : 300,
  };
}

function inputById(id: string | undefined): HTMLInputElement | null {
  if (id === undefined || id === "") return null;
  const element = document.getElementById(id);
  return element instanceof HTMLInputElement ? element : null;
}

const EMPTY_ROOT: JSONNode = {
  type: "root",
  version: 1,
  direction: null,
  format: "",
  indent: 0,
  children: [
    {
      type: "paragraph",
      version: 1,
      direction: null,
      format: "",
      indent: 0,
      textFormat: 0,
      textStyle: "",
      children: [],
    },
  ],
};

// The JSON nodes are checked by Lexical when it parses them.
function asState(root: JSONNode): SerializedEditorState {
  return { root } as unknown as SerializedEditorState;
}

/** An update with this tag came from the server; it is not pushed back. */
const REMOTE_TAG = "kotoba-remote";

let instances = 0;

class Instance {
  private readonly hook: KotobaHook;
  private readonly config: Config;
  private readonly el: HTMLElement;
  private readonly id: string;
  private readonly live: HTMLElement;
  private readonly cleanups: (() => void)[] = [];
  private readonly handlers: unknown[] = [];

  private editor: LexicalEditor | null = null;
  private editable: HTMLElement | null = null;
  private placeholder: HTMLElement | null = null;
  private toolbar: Toolbar | null = null;
  private link: LinkForm | null = null;
  private prompts: Prompts | null = null;
  private uploads: Uploads | null = null;

  private json = "";
  private pushed = "";
  private timer: ReturnType<typeof setTimeout> | undefined;
  private destroyed = false;
  private readonly ready: Promise<void>;

  constructor(hook: KotobaHook) {
    this.hook = hook;
    this.el = hook.el;
    this.config = readConfig(hook.el);
    instances += 1;
    this.id = hook.el.id || `kotoba-${instances}`;

    this.el.classList.add("kotoba");
    this.live = document.createElement("div");
    this.live.className = "kotoba-live";
    this.live.setAttribute("aria-live", "polite");
    this.live.setAttribute("role", "status");

    // Server events are registered at once, so that none is lost while the
    // app node modules load; each one waits for the editor.
    this.on("set_content", (payload) => this.setContent(payload.doc));
    this.on("insert_node", (payload) => this.insertNode(payload.node));
    this.on("set_readonly", (payload) => this.setReadonly(payload.readonly === true));
    this.on("focus", () => this.editor?.focus());
    this.on("kotoba:prompt_results", (payload) => {
      if (typeof payload.prompt === "string") this.prompts?.receive(payload.prompt, payload.items, payload.query);
    });

    this.ready = this.mount();
  }

  private on(event: string, handler: (payload: Record<string, unknown>) => void): void {
    const ref = this.hook.handleEvent(event, (payload: unknown) => {
      if (!isObject(payload)) return;
      if (payload.id !== undefined && payload.id !== this.id) return;
      void this.ready.then(() => {
        if (!this.destroyed && this.editor !== null) handler(payload);
      });
    });
    this.handlers.push(ref);
  }

  private async mount(): Promise<void> {
    const appNodes = await loadNodes(this.config.nodes);
    if (this.destroyed) return;

    const editor = createKotobaEditor({
      namespace: this.id,
      nodes: appNodes,
      editable: !this.config.readonly,
    });
    this.editor = editor;

    const surface = document.createElement("div");
    surface.className = "kotoba-surface";

    const editable = this.el.querySelector<HTMLElement>("[data-kotoba-editable]") ?? document.createElement("div");
    editable.classList.add("kotoba-editable");
    editable.contentEditable = String(!this.config.readonly);
    editable.setAttribute("role", "textbox");
    editable.setAttribute("aria-multiline", "true");
    editable.spellcheck = true;
    copyLabel(this.el, editable);
    if (this.config.readonly) editable.setAttribute("aria-readonly", "true");
    if (this.config.placeholder !== "") editable.setAttribute("aria-placeholder", this.config.placeholder);
    this.editable = editable;

    const placeholder = document.createElement("div");
    placeholder.className = "kotoba-placeholder";
    placeholder.setAttribute("aria-hidden", "true");
    placeholder.textContent = this.config.placeholder;
    this.placeholder = placeholder;

    surface.append(editable, placeholder);
    this.el.append(surface, this.live);

    this.cleanups.push(registerPlugins(editor));

    this.link = createLinkForm(editor, { host: surface, idPrefix: this.id, announce: this.announce });
    this.uploads = createUploads(editor, { host: this.el, target: this.config.upload, announce: this.announce });

    const existing =
      this.el.querySelector<HTMLElement>("[data-kotoba-toolbar]") ??
      (this.el.id ? document.querySelector<HTMLElement>(`[data-kotoba-toolbar="${CSS.escape(this.el.id)}"]`) : null);

    this.toolbar = createToolbar(editor, {
      existing,
      host: this.el,
      label: "Formatting",
      uploads: this.uploads.enabled,
      onLink: () => this.link?.open(),
      onUpload: () => this.uploads?.open(),
      announce: this.announce,
    });
    this.toolbar.setDisabled(this.config.readonly);

    if (this.config.prompts.size > 0) {
      this.prompts = createPrompts(editor, {
        host: surface,
        editable,
        idPrefix: this.id,
        triggers: this.config.prompts,
        request: (prompt, query) => this.push("kotoba:prompt", { v: PROTOCOL_VERSION, prompt, query }),
        announce: this.announce,
      });
    }

    this.cleanups.push(
      editor.registerUpdateListener(({ editorState, dirtyElements, dirtyLeaves, tags }) => {
        this.updatePlaceholder();
        const remote = tags.has(REMOTE_TAG);
        if (!remote && dirtyElements.size === 0 && dirtyLeaves.size === 0) return;

        this.json = JSON.stringify(toEnvelope(editorState));
        if (this.config.input !== null) this.config.input.value = this.json;

        if (remote) {
          this.pushed = this.json;
        } else {
          this.schedulePush();
        }
      }),
      // Vanilla Lexical does not set contenteditable itself.
      editor.registerEditableListener((isEditable) => {
        editable.contentEditable = String(isEditable);
        if (isEditable) editable.removeAttribute("aria-readonly");
        else editable.setAttribute("aria-readonly", "true");
      }),
      editor.registerCommand(
        BLUR_COMMAND,
        () => {
          this.flush();
          return false;
        },
        COMMAND_PRIORITY_LOW,
      ),
    );

    this.watchForm();
    editor.setRootElement(editable);
    this.load(this.config.input?.value ?? "", false);
  }

  // Reads a document into the editor. An empty or invalid document gives an
  // empty editor.
  private load(value: unknown, remote: boolean): void {
    const editor = this.editor;
    if (editor === null) return;

    const root = readRoot(value);
    let state: EditorState | null = null;

    if (root !== null) {
      try {
        state = editor.parseEditorState(asState(prepareRoot(root, registeredTypes(editor))));
      } catch (error) {
        console.error("Kotoba: the document could not be read", error);
      }
    }

    if (state === null || state.isEmpty()) {
      state = editor.parseEditorState(asState(EMPTY_ROOT));
    }

    // Without a change of the document, the first load writes the hidden
    // input but does not push `kotoba:change`.
    editor.setEditorState(state, { tag: REMOTE_TAG });
    if (remote) editor.dispatchCommand(CLEAR_HISTORY_COMMAND, undefined);
    this.uploads?.reset();
    this.prompts?.close();
  }

  private setContent(doc: unknown): void {
    this.load(doc, true);
  }

  private insertNode(json: unknown): void {
    const editor = this.editor;
    if (editor === null || !isObject(json) || typeof json.type !== "string") {
      console.error("Kotoba: insert_node needs a node with a type", json);
      return;
    }
    if (!registeredTypes(editor).has(json.type)) {
      console.error(`Kotoba: insert_node has a node of an unknown type "${json.type}"`);
      return;
    }

    editor.update(() => {
      const node = $parseSerializedNode({ version: 1, ...json } as unknown as SerializedLexicalNode);
      this.uploads?.$insert(node);
    });
  }

  private setReadonly(readonly: boolean): void {
    const { editor, editable } = this;
    if (editor === null || editable === null) return;
    editor.setEditable(!readonly);
    this.toolbar?.setDisabled(readonly);
    if (readonly) this.prompts?.close();
  }

  private updatePlaceholder(): void {
    const { editor, placeholder } = this;
    if (editor === null || placeholder === null) return;
    const empty = editor.getEditorState().read(() => {
      const root = $getRoot();
      const first = root.getFirstChild();
      return (
        root.getChildrenSize() === 0 ||
        (root.getChildrenSize() === 1 && $isParagraphNode(first) && first.getChildrenSize() === 0)
      );
    });
    placeholder.hidden = !empty || this.config.placeholder === "";
  }

  private schedulePush(): void {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.flush(), this.config.debounce);
  }

  private flush(): void {
    clearTimeout(this.timer);
    this.timer = undefined;
    if (this.destroyed || this.json === "" || this.json === this.pushed) return;
    this.pushed = this.json;
    this.push("kotoba:change", { v: PROTOCOL_VERSION, doc: JSON.parse(this.json) as DocumentEnvelope });
  }

  private push(event: string, payload: object): void {
    const target = this.el.getAttribute("phx-target");
    if (target !== null && target !== "") this.hook.pushEventTo(target, event, payload);
    else this.hook.pushEvent(event, payload);
  }

  // LiveView builds the form data for phx-change and phx-submit with
  // `new FormData(form)`. The `formdata` event puts the current document in
  // it, even when a patch from the server has reset the hidden input.
  private watchForm(): void {
    const input = this.config.input;
    const form = input?.form;
    if (input === null || !form) return;

    const onFormData = (event: FormDataEvent): void => {
      if (this.json !== "" && input.name !== "") event.formData.set(input.name, this.json);
    };
    const onSubmit = (): void => {
      if (this.json !== "") input.value = this.json;
    };

    form.addEventListener("formdata", onFormData);
    form.addEventListener("submit", onSubmit, true);
    this.cleanups.push(() => {
      form.removeEventListener("formdata", onFormData);
      form.removeEventListener("submit", onSubmit, true);
    });
  }

  private readonly announce = (message: string): void => {
    this.live.textContent = "";
    window.setTimeout(() => {
      this.live.textContent = message;
    }, 50);
  };

  destroy(): void {
    this.destroyed = true;
    clearTimeout(this.timer);
    for (const ref of this.handlers) this.hook.removeHandleEvent(ref);
    this.prompts?.dispose();
    this.toolbar?.dispose();
    this.link?.dispose();
    this.uploads?.dispose();
    for (const cleanup of this.cleanups.reverse()) cleanup();
    this.editor?.setRootElement(null);
    this.editor = null;
  }
}

// The editable element takes the label of the hook element.
function copyLabel(from: HTMLElement, to: HTMLElement): void {
  for (const name of ["aria-label", "aria-labelledby", "aria-describedby"]) {
    const value = from.getAttribute(name);
    if (value !== null && !to.hasAttribute(name)) {
      to.setAttribute(name, value);
      from.removeAttribute(name);
    }
  }
}

/** The LiveView hook. */
export const Kotoba = {
  mounted(this: KotobaHook): void {
    this.kotoba = new Instance(this);
  },
  destroyed(this: KotobaHook): void {
    this.kotoba?.destroy();
    this.kotoba = undefined;
  },
};
