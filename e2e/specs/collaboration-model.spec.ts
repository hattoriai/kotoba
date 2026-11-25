import { expect, test } from "@playwright/test";

import { apply, type Atom, type Attrs, type Operation, type State } from "../../assets/src/collab/model";
import { apply as copyingApply } from "./collaboration-model-oracle";

const DOCUMENTS = 80;
const STEPS = 40;

type Outcome = { ok: true; json: string; state: State } | { ok: false; reason: string };

function outcome(run: () => State): Outcome {
  try {
    const state = run();
    return { ok: true, json: JSON.stringify(state), state };
  } catch (error) {
    return { ok: false, reason: error instanceof Error ? `${error.name}: ${error.message}` : String(error) };
  }
}

const comparable = (result: Outcome) => (result.ok ? { ok: true, json: result.json } : result);
const copy = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;

function freeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) freeze(child);
  }
  return value;
}

function generator(seed: number): () => number {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

class Author {
  private next = 0;
  constructor(private readonly random: () => number) {}

  chance(p: number): boolean { return this.random() < p; }
  int(n: number): number { return Math.floor(this.random() * n); }
  pick<T>(items: readonly T[]): T { return items[this.int(items.length)]; }
  fresh(prefix: string): string { return `${prefix}:${++this.next}`; }

  ref(items: readonly string[]): string {
    return items.length === 0 || this.chance(0.04) ? "ghost" : this.pick(items);
  }

  textAttrs(): Attrs {
    return { type: "text", version: 1, bold: this.chance(0.3), italic: this.chance(0.2), ...(this.chance(0.2) ? { style: "color: red" } : {}) };
  }

  value(): unknown {
    return this.pick([0, 2, "", "center", "https://example.com", null, true, { level: 2 }, ["a", "b"]]);
  }

  transaction(state: State): Operation[] {
    const nodes = Object.keys(state.nodes);
    const pools = {
      nodes,
      elements: nodes.filter(id => state.nodes[id].element),
      buffers: Object.keys(state.texts),
      atoms: [...new Set(Object.values(state.texts).flat().filter(atom => !atom.moved_to).map(atom => atom.id))],
    };
    const length = this.chance(0.1) ? 6 + this.int(6) : 1 + this.int(4);
    return Array.from({ length }, () => this.operation(state, pools));
  }

  private operation(state: State, pools: { nodes: string[]; elements: string[]; buffers: string[]; atoms: string[] }): Operation {
    const tags = ["t1", "t2", "t3"];
    const live = (buffer: string): Atom[] => (state.texts[buffer] ?? []).filter(atom => !atom.moved_to);
    const someAtoms = (): string[] => [...new Set(Array.from({ length: 1 + this.int(3) }, () => this.ref(pools.atoms)))];
    const notRoot = pools.nodes.filter(id => id !== state.root);
    switch (this.pick(["insert_node", "move_node", "node_visibility", "set_attrs", "insert_text", "insert_text", "move_text", "text_visibility", "set_text_attrs"] as const)) {
      case "insert_node": {
        const type = this.pick(["paragraph", "text", "text", "heading", "quote", "image"]);
        const parent = this.ref(type === "text" || this.chance(0.8) ? pools.elements : pools.nodes);
        const order = state.orders[parent] ?? [];
        const after = this.chance(0.3) || order.length === 0 ? null : this.chance(0.05) ? "ghost" : this.pick(order);
        const id = this.chance(0.03) ? this.ref(pools.nodes) : this.fresh("n");
        const data: Attrs = { type, version: 1, ...(this.chance(0.3) ? { format: this.pick(["", "center"]), indent: this.int(3) } : {}) };
        pools.nodes.push(id);
        if (type === "text") pools.buffers.push(id);
        else if (type !== "image") pools.elements.push(id);
        return { op: "insert_node", id, parent, after, data, ...(this.chance(0.5) ? { element: type !== "text" && type !== "image" } : {}) };
      }
      case "move_node": {
        const id = this.chance(0.03) ? state.root : this.ref(notRoot);
        const inside = (candidate: string): boolean => {
          for (let cursor: string | null | undefined = candidate, depth = 0; cursor && depth < 100; cursor = state.nodes[cursor]?.parent, depth++) if (cursor === id) return true;
          return false;
        };
        const parent = this.ref(pools.elements.filter(candidate => !inside(candidate)));
        const order = state.orders[parent] ?? [];
        const after = this.chance(0.4) || order.length === 0 ? null : this.pick(order);
        const node = state.nodes[id];
        return {
          op: "move_node", id, parent, after,
          ...(this.chance(0.8) ? { stamp: this.fresh("m") } : {}),
          ...(this.chance(0.2) ? { expected: { parent: this.chance(0.6) ? node?.parent ?? null : "elsewhere" } } : {}),
          ...(this.chance(0.2) ? { expected_move: this.chance(0.6) ? node?.move_version ?? null : "other" } as { expected_move: string } : {}),
        };
      }
      case "node_visibility":
        return { op: "node_visibility", id: this.chance(0.02) ? state.root : this.ref(notRoot), deleted: this.chance(0.35), tag: this.pick(tags), ...(this.chance(0.4) ? { if_empty: this.chance(0.7) } : {}) };
      case "set_attrs": {
        const id = this.ref(pools.nodes);
        const keys = [...new Set([this.pick(["format", "indent", "url", "tag"]), this.pick(["format", "indent", "url", "tag"])])];
        const values = Object.fromEntries(keys.map(key => [key, this.value()]));
        const node = state.nodes[id];
        return {
          op: "set_attrs", id, values,
          ...(this.chance(0.8) ? { stamp: this.fresh("v") } : {}),
          ...(this.chance(0.2) ? { expected: Object.fromEntries(keys.map(key => [key, this.chance(0.6) ? node?.data[key] ?? null : "nope"])) } : {}),
          ...(this.chance(0.2) ? { expected_versions: Object.fromEntries(keys.map(key => [key, this.chance(0.6) ? node?.versions[key] ?? null : "nope"])) as Record<string, string> } : {}),
        };
      }
      case "insert_text": {
        const id = this.chance(0.05) ? this.ref(pools.elements) : this.ref(pools.buffers);
        const here = live(id).map(atom => atom.id);
        const after = this.chance(0.3) ? null : this.chance(0.7) && here.length > 0 ? this.pick(here) : this.ref(pools.atoms);
        const atoms = Array.from({ length: 1 + this.int(4) }, () => ({
          id: this.chance(0.02) ? this.ref(pools.atoms) : this.fresh("a"),
          text: this.pick(["a", "b", " ", "é", "😀"]),
          ...(this.chance(0.3) ? { attrs: this.textAttrs() } : {}),
        }));
        const op: Operation = { op: "insert_text", id, after, atoms, ...(this.chance(0.6) ? { attrs: this.textAttrs() } : {}) };
        if (this.chance(0.3)) {
          op.inherit = this.ref(pools.atoms);
          if (this.chance(0.7)) op.base_attrs = this.textAttrs();
        }
        pools.atoms.push(...atoms.map(atom => atom.id));
        return op;
      }
      case "move_text": {
        const id = this.ref(pools.buffers);
        const atoms = someAtoms();
        const here = live(id).map(atom => atom.id);
        const after = this.chance(0.4) || here.length === 0 ? null : this.pick(here);
        const moved = (atom: string) => Object.values(state.texts).flat().find(value => value.id === atom && !value.moved_to)?.move_version;
        return {
          op: "move_text", id, after, atoms, stamp: this.fresh("s"),
          ...(this.chance(0.3) ? { expected_moves: Object.fromEntries(atoms.map(atom => [atom, this.chance(0.6) ? moved(atom) ?? "none" : "other"])) } : {}),
        };
      }
      case "text_visibility":
        return { op: "text_visibility", id: this.ref(pools.buffers), atoms: someAtoms(), deleted: this.chance(0.6), tag: this.pick(tags) };
      case "set_text_attrs": {
        const values: Attrs = { bold: this.chance(0.5), ...(this.chance(0.3) ? { italic: this.chance(0.5) } : {}) };
        return {
          op: "set_text_attrs", id: this.ref(pools.buffers), atoms: someAtoms(), values,
          ...(this.chance(0.8) ? { stamp: this.fresh("f") } : {}),
          ...(this.chance(0.15) ? { expected: { bold: this.chance(0.5) } } : {}),
          ...(this.chance(0.15) ? { expected_versions: { bold: this.chance(0.5) ? "f:1" : "nope" } } : {}),
        };
      }
    }
  }
}

const empty: State = {
  v: 1, schema: 1, epoch: "e", revision: 0, root: "root",
  nodes: { root: { data: { type: "root", version: 1 }, parent: null, element: true, deleted: false, deletions: [], versions: {} } },
  orders: { root: [] },
  texts: {},
};

const opening: Operation[] = [
  { op: "insert_node", id: "p1", parent: "root", after: null, data: { type: "paragraph", version: 1 }, element: true },
  { op: "insert_node", id: "b1", parent: "p1", after: null, data: { type: "text", version: 1 }, element: false },
  { op: "insert_text", id: "b1", after: null, attrs: { type: "text", version: 1 }, atoms: Array.from("Hello there", (text, index) => ({ id: `h:${index}`, text })) },
  { op: "insert_node", id: "p2", parent: "root", after: "p1", data: { type: "quote", version: 1 }, element: true },
  { op: "insert_node", id: "b2", parent: "p2", after: null, data: { type: "text", version: 1 }, element: false },
  { op: "insert_text", id: "b2", after: null, attrs: { type: "text", version: 1, bold: true }, atoms: Array.from("World", (text, index) => ({ id: `w:${index}`, text })) },
];

test("apply gives what the copying apply gave, and changes neither the state nor the operations", () => {
  let applied = 0;
  let refused = 0;
  const kinds = new Map<string, number>();
  for (let document = 0; document < DOCUMENTS; document++) {
    const seed = 1000 + document;
    const author = new Author(generator(seed));
    let state = freeze(apply(empty, opening));
    let earlier = state;
    for (let step = 0; step < STEPS; step++) {
      for (const base of [state, earlier]) {
        const ops = freeze(author.transaction(base));
        const before = JSON.stringify(base);
        const sent = JSON.stringify(ops);
        const expected = outcome(() => copyingApply(copy(base), copy(ops)));
        const actual = outcome(() => apply(base, ops));
        const where = `seed ${seed}, step ${step}: ${sent}`;
        expect(comparable(actual), where).toEqual(comparable(expected));
        expect(JSON.stringify(base), `the state given, ${where}`).toBe(before);
        expect(JSON.stringify(ops), `the operations given, ${where}`).toBe(sent);
        if (actual.ok) applied++;
        else refused++;
        for (const op of ops) kinds.set(op.op, (kinds.get(op.op) ?? 0) + 1);
        if (base === state && actual.ok) {
          earlier = state;
          state = freeze(actual.state);
        }
      }
    }
  }
  expect(applied).toBeGreaterThan(DOCUMENTS * STEPS * 0.3);
  expect(refused).toBeGreaterThan(DOCUMENTS * STEPS * 0.1);
  for (const kind of ["insert_node", "move_node", "node_visibility", "set_attrs", "insert_text", "move_text", "text_visibility", "set_text_attrs"]) expect(kinds.get(kind) ?? 0, kind).toBeGreaterThan(1000);
});
