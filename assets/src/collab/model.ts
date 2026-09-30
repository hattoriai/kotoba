/** Kotoba's versioned semantic protocol. No editor or transport dependency. */
export type Attrs = Record<string, unknown>;
export interface ModelNode { data: Attrs; parent: string | null; element: boolean; deleted: boolean; deletions: string[]; versions: Record<string, string | null>; move_version?: string | null }
export interface Atom { id: string; text: string; attrs: Attrs; deleted: boolean; deletions: string[]; versions: Record<string, string>; moved_to?: string; move_version?: string }
export interface InsertedAtom { id: string; text: string; attrs?: Attrs }
export interface State { v: 1; schema: 1; epoch: string; revision: number; root: string; nodes: Record<string, ModelNode>; orders: Record<string, string[]>; texts: Record<string, Atom[]> }
interface Stamped { stamp?: string; expected?: Attrs; expected_versions?: Record<string, string> }
export type Operation =
  | { op: "insert_node"; id: string; parent: string; after: string | null; data: Attrs; element?: boolean }
  | ({ op: "move_node"; id: string; parent: string; after: string | null; expected_move?: string } & Stamped)
  | { op: "node_visibility"; id: string; deleted: boolean; tag: string; if_empty?: boolean }
  | ({ op: "set_attrs"; id: string; values: Attrs } & Stamped)
  | { op: "move_text"; id: string; after: string | null; atoms: string[]; stamp: string; expected_moves?: Record<string, string> }
  | { op: "insert_text"; id: string; after: string | null; atoms: InsertedAtom[]; attrs?: Attrs; inherit?: string; base_attrs?: Attrs }
  | { op: "text_visibility"; id: string; atoms: string[]; deleted: boolean; tag: string }
  | ({ op: "set_text_attrs"; id: string; atoms: string[]; values: Attrs } & Stamped);
export interface Transaction { v: 1; schema: 1; epoch: string; id: string; base_revision: number; ops: Operation[]; revision?: number }
export interface WireNode { type: string; children?: WireNode[]; [key: string]: unknown }
export interface Envelope { kotoba: 1; lexical: "0.51"; root: WireNode }

export const MARKS = ["bold", "italic", "strikethrough", "underline", "code", "subscript", "superscript", "highlight", "lowercase", "uppercase", "capitalize"] as const;
export const TEXT_TYPES = new Set(["text", "code-highlight", "tab"]);
export const uuid = (): string => crypto.randomUUID();
export const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
export function equal(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return false;
  if (Array.isArray(a) || Array.isArray(b)) return Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((value, index) => equal(value, b[index]));
  const first = a as Attrs;
  const second = b as Attrs;
  return Object.keys(first).length === Object.keys(second).length && Object.keys(first).every(key => Object.hasOwn(second, key) && equal(first[key], second[key]));
}
export const children = (state: State, id: string): string[] => (state.orders[id] ?? []).filter(child => state.nodes[child]?.parent === id && !state.nodes[child]?.deleted);
export const visibleAtoms = (state: State, id: string): Atom[] => (state.texts[id] ?? []).filter(atom => !atom.deleted && !atom.moved_to);

export function textAttrs(node: Attrs): Attrs {
  const attrs = { ...node };
  delete attrs.text;
  delete attrs.children;
  delete attrs.format;
  const format = typeof node.format === "number" ? node.format : 0;
  MARKS.forEach((mark, bit) => { attrs[mark] = (format & (1 << bit)) !== 0; });
  return attrs;
}

export function textJSON(attrs: Attrs, text: string): WireNode {
  const data = { ...attrs, type: String(attrs.type ?? "text"), text, format: 0 };
  MARKS.forEach((mark, bit) => { if (attrs[mark]) data.format |= 1 << bit; delete (data as Attrs)[mark]; });
  return data;
}

export function spans(state: State, id: string): { atoms: Atom[]; json: WireNode }[] {
  const groups: Atom[][] = [];
  for (const atom of visibleAtoms(state, id)) {
    const previous = groups[groups.length - 1];
    if (previous && equal(previous[0].attrs, atom.attrs)) previous.push(atom);
    else groups.push([atom]);
  }
  return groups.map(atoms => ({ atoms, json: textJSON(atoms[0].attrs, atoms.map(atom => atom.text).join("")) }));
}

export function envelope(state: State): Envelope {
  const node = (id: string): WireNode => {
    const data = state.nodes[id].data;
    const json = { ...data, type: String(data.type) } as WireNode;
    if (Object.hasOwn(state.orders, id) && !Object.hasOwn(state.texts, id)) {
      const list = children(state, id).flatMap(child => Object.hasOwn(state.texts, child) ? spans(state, child).map(span => span.json) : [node(child)]);
      // Leaf nodes have an empty order too; only elements own `children`.
      if (state.nodes[id].element) json.children = list;
    }
    return json;
  };
  return { kotoba: 1, lexical: "0.51", root: node(state.root) };
}

export function atomLocation(state: State, id: string | null | undefined): string | null {
  if (!id) return null;
  return Object.keys(state.texts).find(buffer => state.texts[buffer].some(atom => atom.id === id && !atom.moved_to)) ?? null;
}
export function findAtom(state: State, id: string): Atom | undefined {
  const buffer = atomLocation(state, id);
  return buffer ? state.texts[buffer].find(atom => atom.id === id && !atom.moved_to) : undefined;
}

function live(state: State, id: string): ModelNode {
  const node = state.nodes[id];
  if (!node) throw new Error("unknown_node");
  if (node.deleted) throw new Error("deleted_target");
  if (node.parent) live(state, node.parent);
  return node;
}

function anchorIndex<T>(items: T[], anchor: string | null, getId: (item: T) => string): number {
  if (anchor === null) return 0;
  const index = items.findIndex(item => getId(item) === anchor);
  if (index < 0) throw new Error("unknown_anchor");
  return index + 1;
}

function visibility(record: ModelNode | Atom, tag: string, deleted: boolean): void {
  record.deletions = deleted ? [...new Set([tag, ...(record.deletions ?? [])])] : (record.deletions ?? []).filter(value => value !== tag);
  record.deleted = record.deletions.length > 0;
}

function empty(state: State, id: string): boolean {
  if (state.texts[id]) return visibleAtoms(state, id).length === 0;
  if (!state.nodes[id].element) return false;
  return children(state, id).every(child => empty(state, child));
}

function patch(data: Attrs, versions: Record<string, string | null>, values: Attrs, op: Stamped): void {
  for (const [key, value] of Object.entries(values)) {
    if (op.expected_versions && Object.hasOwn(op.expected_versions, key) && (versions[key] ?? null) !== op.expected_versions[key]) continue;
    if (op.expected && Object.hasOwn(op.expected, key) && !equal(data[key] ?? null, op.expected[key])) continue;
    data[key] = clone(value);
    versions[key] = op.stamp ?? null;
  }
}

/** Replay accepted operations, or overlay provisional operations on a snapshot. */
export function apply(state: State, operations: Operation[]): State {
  const result = clone(state);
  for (const op of operations) {
    switch (op.op) {
      case "insert_node": {
        live(result, op.parent);
        if (result.nodes[op.id]) throw new Error("id_reused");
        const order = result.orders[op.parent] ?? [];
        order.splice(anchorIndex(order, op.after, value => value), 0, op.id);
        result.orders[op.parent] = order;
        result.nodes[op.id] = { data: clone(op.data), parent: op.parent, element: op.element ?? new Set(["paragraph", "heading", "quote", "list", "listitem", "link", "autolink", "code", "table", "tablerow", "tablecell", "gallery"]).has(String(op.data.type)), deleted: false, deletions: [], versions: {} };
        result.orders[op.id] = [];
        if (op.data.type === "text") result.texts[op.id] = [];
        break;
      }
      case "move_node": {
        const node = live(result, op.id);
        live(result, op.parent);
        if (op.expected && Object.entries(op.expected).some(([key, value]) => !equal((node as unknown as Attrs)[key], value))) break;
        if (Object.hasOwn(op, "expected_move") && (node.move_version ?? null) !== op.expected_move) break;
        const order = (result.orders[op.parent] ?? []).filter(id => id !== op.id);
        order.splice(anchorIndex(order, op.after, value => value), 0, op.id);
        result.orders[op.parent] = order;
        node.parent = op.parent;
        node.move_version = op.stamp ?? null;
        break;
      }
      case "node_visibility":
        if (!op.deleted || !op.if_empty || empty(result, op.id)) visibility(result.nodes[op.id], op.tag, op.deleted);
        break;
      case "set_attrs": {
        const node = live(result, op.id);
        patch(node.data, node.versions, op.values, op);
        break;
      }
      case "insert_text": {
        const target = atomLocation(result, op.after) ?? atomLocation(result, op.inherit) ?? op.id;
        live(result, target);
        const atoms = result.texts[target];
        const inherited = op.inherit ? findAtom(result, op.inherit) : undefined;
        const inserted = clone(op.atoms).map(atom => {
          let attrs = atom.attrs ?? op.attrs ?? {};
          if (inherited && op.base_attrs) {
            const overrides = Object.fromEntries(Object.entries(attrs).filter(([key, value]) => !equal(op.base_attrs![key], value)));
            attrs = { ...inherited.attrs, ...overrides };
          }
          return { id: atom.id, text: atom.text, attrs, deleted: false, deletions: [], versions: {} };
        });
        const index = target !== op.id && op.after === null && op.inherit ? anchorIndex(atoms, op.inherit, atom => atom.id) - 1 : anchorIndex(atoms, op.after, atom => atom.id);
        atoms.splice(index, 0, ...inserted);
        break;
      }
      case "move_text": {
        live(result, op.id);
        const eligible = op.atoms.filter(id => !op.expected_moves || !Object.hasOwn(op.expected_moves, id) || findAtom(result, id)?.move_version === op.expected_moves[id]);
        const moving = eligible.map(id => { const atom = clone(findAtom(result, id)!); delete atom.moved_to; atom.move_version = op.stamp; return atom; });
        for (const [buffer, atoms] of Object.entries(result.texts)) {
          result.texts[buffer] = buffer === op.id ? atoms.filter(atom => !eligible.includes(atom.id)) : atoms.map(atom => eligible.includes(atom.id) && !atom.moved_to ? { ...atom, moved_to: op.id } : atom);
        }
        const target = result.texts[op.id];
        target.splice(anchorIndex(target, op.after, atom => atom.id), 0, ...moving);
        break;
      }
      case "text_visibility":
      case "set_text_attrs": {
        const locations = op.atoms.map(id => atomLocation(result, id));
        if (locations.some(value => value === null)) throw new Error("unknown_atom");
        locations.forEach(buffer => live(result, buffer!));
        const targets = new Set(op.atoms);
        for (const atom of Object.values(result.texts).flat()) {
          if (!targets.has(atom.id) || atom.moved_to) continue;
          if (op.op === "text_visibility") visibility(atom, op.tag, op.deleted);
          else patch(atom.attrs, atom.versions, op.values, op);
        }
        break;
      }
    }
  }
  return result;
}
