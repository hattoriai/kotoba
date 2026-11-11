// The copying apply from assets/src/collab/model.ts at 5039f43, kept as the
// oracle for collaboration-model.spec.ts.

import type { Atom, Attrs, ModelNode, Operation, State } from "../../assets/src/collab/model";

type Stamped = { stamp?: string; expected?: Attrs; expected_versions?: Record<string, string> };

const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
function equal(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return false;
  if (Array.isArray(a) || Array.isArray(b)) return Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((value, index) => equal(value, b[index]));
  const first = a as Attrs;
  const second = b as Attrs;
  return Object.keys(first).length === Object.keys(second).length && Object.keys(first).every(key => Object.hasOwn(second, key) && equal(first[key], second[key]));
}
const children = (state: State, id: string): string[] => (state.orders[id] ?? []).filter(child => state.nodes[child]?.parent === id && !state.nodes[child]?.deleted);
const visibleAtoms = (state: State, id: string): Atom[] => (state.texts[id] ?? []).filter(atom => !atom.deleted && !atom.moved_to);

function atomLocation(state: State, id: string | null | undefined): string | null {
  if (!id) return null;
  return Object.keys(state.texts).find(buffer => state.texts[buffer].some(atom => atom.id === id && !atom.moved_to)) ?? null;
}
function findAtom(state: State, id: string): Atom | undefined {
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
          let attrs = atom.attrs ?? clone(op.attrs ?? {});
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
