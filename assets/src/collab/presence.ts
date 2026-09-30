import type { CollaborationHost } from "../collaboration";
import type { Binding, SharedSelection } from "./binding";

export interface Person { session: string; role: "read" | "write"; user: { id: string; name: string; color: string }; selection: SharedSelection | null }

export class Presence {
  private readonly list: HTMLUListElement;
  private readonly layer: HTMLDivElement;
  private people: Person[] = [];
  private frame = 0;
  private known = new Set<string>();
  private initialized = false;
  private readonly observer: ResizeObserver;

  constructor(private readonly host: CollaborationHost, private readonly binding: Binding, private readonly session: () => string, bar: HTMLElement) {
    this.list = document.createElement("ul");
    this.list.className = "kotoba-collab-people";
    this.list.setAttribute("aria-label", "People in this document");
    bar.append(this.list);
    this.layer = document.createElement("div");
    this.layer.className = "kotoba-collab-cursors";
    this.layer.setAttribute("aria-hidden", "true");
    host.surface.append(this.layer);
    this.observer = new ResizeObserver(() => this.draw());
    this.observer.observe(host.surface);
    window.addEventListener("scroll", this.onScroll, true);
  }

  receive(people: Person[]): void {
    this.people = people;
    const unique = new Map(people.map(person => [person.user.id, person]));
    const next = new Set(unique.keys());
    if (this.initialized) {
      for (const [id, person] of unique) if (!this.known.has(id)) this.host.announce(`${person.user.name} joined`);
      for (const id of this.known) if (!next.has(id)) this.host.announce("A participant left");
    }
    this.initialized = true;
    this.known = next;
    this.list.replaceChildren(...[...unique.values()].map(person => {
      const item = document.createElement("li");
      item.textContent = `${person.user.name}${person.role === "read" ? " (viewing)" : ""}`;
      item.style.setProperty("--collab-color", this.color(person));
      return item;
    }));
    this.draw();
  }

  offline(): void { this.receive(this.people.filter(person => person.session === this.session())); }
  private color(person: Person): string { return /^#[0-9a-f]{6}$/i.test(person.user.color) ? person.user.color : "#2563eb"; }
  private readonly onScroll = (): void => this.draw();

  draw(): void {
    cancelAnimationFrame(this.frame);
    this.frame = requestAnimationFrame(() => {
      this.layer.replaceChildren();
      const surface = this.host.surface.getBoundingClientRect();
      for (const person of this.people) {
        if (person.session === this.session() || !person.selection || person.role === "read") continue;
        const anchor = this.binding.domPoint(person.selection.anchor);
        const focus = this.binding.domPoint(person.selection.focus);
        if (!anchor || !focus) continue;
        try {
          const range = document.createRange();
          range.setStart(anchor.node, anchor.offset);
          range.setEnd(focus.node, focus.offset);
          // Reverse selections need their endpoints swapped for a DOM Range.
          if (range.collapsed && (anchor.node !== focus.node || anchor.offset !== focus.offset)) {
            range.setStart(focus.node, focus.offset);
            range.setEnd(anchor.node, anchor.offset);
          }
          for (const rect of Array.from(range.getClientRects())) {
            if (rect.width === 0) continue;
            const highlight = document.createElement("span");
            highlight.className = "kotoba-collab-selection";
            this.position(highlight, rect, surface);
            highlight.style.backgroundColor = this.color(person);
            this.layer.append(highlight);
          }
          const caretRange = document.createRange();
          caretRange.setStart(focus.node, focus.offset);
          caretRange.collapse(true);
          const rect = caretRange.getClientRects()[0];
          if (!rect) continue;
          const caret = document.createElement("span");
          caret.className = "kotoba-collab-caret";
          this.position(caret, rect, surface);
          caret.style.setProperty("--collab-color", this.color(person));
          const label = document.createElement("span");
          label.textContent = person.user.name;
          label.style.backgroundColor = this.color(person);
          caret.append(label);
          this.layer.append(caret);
        } catch { /* A DOM reconciliation can briefly detach an awareness anchor. */ }
      }
    });
  }

  private position(element: HTMLElement, rect: DOMRect, surface: DOMRect): void {
    element.style.left = `${rect.left - surface.left}px`;
    element.style.top = `${rect.top - surface.top}px`;
    element.style.width = `${rect.width}px`;
    element.style.height = `${rect.height || 20}px`;
  }

  dispose(): void {
    cancelAnimationFrame(this.frame);
    this.observer.disconnect();
    window.removeEventListener("scroll", this.onScroll, true);
    this.list.remove();
    this.layer.remove();
  }
}
