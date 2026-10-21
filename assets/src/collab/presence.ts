import { follow, following, onFollow, stopOnOwnWay } from "issho";
import type { CollaborationHost } from "../collaboration";
import type { Binding, SharedSelection } from "./binding";

export interface Person { session: string; role: "read" | "write"; user: { id: string; name: string; color: string }; selection: SharedSelection | null }

export class Presence {
  private readonly list: HTMLUListElement;
  private readonly layer: HTMLDivElement;
  private people: Person[] = [];
  private readonly lastSelections = new Map<string, SharedSelection>();
  // A caret is kept from one drawing to the next, so that it glides to its new place.
  private readonly carets = new Map<string, HTMLSpanElement>();
  // Whether each person had only a caret when last drawn: a selection made from it sweeps from its start to its end.
  private readonly wasCaret = new Map<string, boolean>();
  // When each sweep began: a drawing during one goes on with it, rather than starting it again.
  private readonly sweeps = new Map<string, number>();
  private frame = 0;
  private known = new Set<string>();
  private initialized = false;
  private readonly observer: ResizeObserver;

  // `list`: whether the editor lists the people, or the page does (Issho's people list).
  private readonly stopFollowing: () => void;
  // "Following Ada", with Stop, when the editor lists its people.
  private readonly followingLine: HTMLElement;
  // The caret last scrolled to, for the one followed: once for each place they go.
  private scrolledTo = "";

  // `room`: following is the room's (Issho's): someone followed in it, from
  // this list or the page's, is followed to their caret.
  constructor(private readonly host: CollaborationHost, private readonly binding: Binding, private readonly session: () => string, bar: HTMLElement, private readonly listed = true, private readonly room = "") {
    this.list = document.createElement("ul");
    this.list.className = "kotoba-collab-people";
    this.list.setAttribute("aria-label", "People in this document");
    this.followingLine = document.createElement("p");
    // Issho's look of following (its classes and properties), the same on every block of the page.
    this.followingLine.className = "kotoba-collab-following issho-following";
    this.followingLine.setAttribute("role", "status");
    this.followingLine.dataset.isshoFollowControl = "";
    this.followingLine.hidden = true;
    if (listed) bar.append(this.list, this.followingLine);
    this.layer = document.createElement("div");
    this.layer.className = "kotoba-collab-cursors";
    this.layer.setAttribute("aria-hidden", "true");
    host.surface.append(this.layer);
    const offFollow = room ? onFollow(room, () => this.receive(this.people)) : () => {};
    const offOwnWay = room ? stopOnOwnWay(room, host.element) : () => {};
    this.stopFollowing = () => {
      offFollow();
      offOwnWay();
    };
    this.observer = new ResizeObserver(() => this.draw());
    this.observer.observe(host.surface);
    window.addEventListener("scroll", this.onScroll, true);
  }

  receive(people: Person[]): void {
    this.people = people;
    const sessions = new Set(people.filter(person => person.selection && person.role === "write").map(person => person.session));
    for (const session of this.lastSelections.keys()) if (!sessions.has(session)) this.lastSelections.delete(session);
    const unique = new Map(people.map(person => [person.user.id, person]));
    const next = new Set(unique.keys());
    if (this.initialized && this.listed) {
      for (const [id, person] of unique) if (!this.known.has(id)) this.host.announce(`${person.user.name} joined`);
      for (const id of this.known) if (!next.has(id)) this.host.announce("A participant left");
    }
    this.initialized = true;
    this.known = next;
    this.list.replaceChildren(...[...unique.values()].map(person => {
      const item = document.createElement("li");
      const text = `${person.user.name}${person.role === "read" ? " (viewing)" : ""}`;
      item.style.setProperty("--collab-color", this.color(person));
      // Someone else: a button that follows them, in the room, to their caret.
      if (!this.room || person.session === this.session() || person.user.id === this.host.credentials.user.id) {
        item.textContent = text;
        return item;
      }
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = text;
      button.dataset.isshoFollowControl = "";
      button.setAttribute("aria-pressed", String(following(this.room) === person.user.id));
      button.addEventListener("click", () => follow(this.room, following(this.room) === person.user.id ? null : person.user.id));
      item.append(button);
      return item;
    }));
    this.showFollowing(unique);
    this.draw();
  }

  // Whom the room follows, when they are in this editor and it lists its
  // people (on an Issho page, the page's people list says it): a line in
  // their colour, with Stop, and a ring of it around the editor.
  private showFollowing(unique: Map<string, Person>): void {
    const key = this.room ? following(this.room) : null;
    const person = key && key !== this.host.credentials.user.id ? unique.get(key) : undefined;
    const element = this.host.element;
    if (!this.listed || !person) {
      this.followingLine.hidden = true;
      this.followingLine.replaceChildren();
      delete element.dataset.collabFollowing;
      element.style.removeProperty("--collab-follow-color");
      return;
    }
    const color = this.color(person);
    element.dataset.collabFollowing = "";
    element.style.setProperty("--collab-follow-color", color);
    this.followingLine.style.setProperty("--issho-color", color);
    const text = document.createElement("span");
    text.textContent = `Following ${person.user.name}`;
    const stop = document.createElement("button");
    stop.type = "button";
    stop.className = "kotoba-collab-following-stop issho-following-stop";
    stop.textContent = "Stop";
    stop.addEventListener("click", () => follow(this.room, null));
    this.followingLine.replaceChildren(text, stop);
    this.followingLine.hidden = false;
  }

  offline(): void { this.receive(this.people.filter(person => person.session === this.session())); }
  // A person's own colour, or their colour of Issho's palette (the same as in Issho's people list).
  private color(person: Person): string { return /^#[0-9a-f]{6}$/i.test(person.user.color) || /^var\(--issho-person-[1-8], #[0-9a-f]{6}\)$/i.test(person.user.color) ? person.user.color : "#2563eb"; }
  private readonly onScroll = (): void => this.draw();

  draw(): void {
    cancelAnimationFrame(this.frame);
    this.frame = requestAnimationFrame(() => {
      for (const highlight of Array.from(this.layer.querySelectorAll(".kotoba-collab-selection"))) highlight.remove();
      const surface = this.host.surface.getBoundingClientRect();
      const drawn = new Set<string>();
      for (const person of this.people) {
        if (person.session === this.session() || !person.selection || person.role === "read") continue;
        let anchor = this.binding.domPoint(person.selection.anchor);
        let focus = this.binding.domPoint(person.selection.focus);
        if (anchor && focus) this.lastSelections.set(person.session, person.selection);
        else {
          // Keep the last resolvable selection until the document catches up with awareness.
          const previous = this.lastSelections.get(person.session);
          if (previous) {
            anchor = this.binding.domPoint(previous.anchor);
            focus = this.binding.domPoint(previous.focus);
          }
        }
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
          // Only where a selection goes is sent: a new one is drawn as a drag
          // makes it, a line after another, from its start to its end.
          // A caret has no highlight (a collapsed range can still have a sliver of a rectangle).
          const rects = range.collapsed ? [] : lines(Array.from(range.getClientRects()).filter(rect => rect.width > 0));
          if (!range.collapsed && this.wasCaret.get(person.session) === true) this.sweeps.set(person.session, performance.now());
          this.wasCaret.set(person.session, range.collapsed);
          const began = this.sweeps.get(person.session);
          const elapsed = began === undefined ? Infinity : performance.now() - began;
          if (elapsed > 2_000) this.sweeps.delete(person.session);
          const sweep = rects.length > 0 && elapsed <= 2_000;
          rects.forEach((rect, line) => {
            const highlight = document.createElement("span");
            highlight.className = "kotoba-collab-selection";
            this.position(highlight, rect, surface);
            highlight.style.backgroundColor = this.color(person);
            if (sweep) {
              highlight.dataset.sweep = "";
              highlight.style.setProperty("--collab-sweep-line", `${line / rects.length}`);
              highlight.style.setProperty("--collab-sweep-lines", `${rects.length}`);
              highlight.style.setProperty("--collab-sweep-elapsed", `${Math.round(elapsed)}ms`);
            }
            // Under the carets.
            this.layer.prepend(highlight);
          });
          const rect = caretRect(focus);
          if (!rect) continue;
          let caret = this.carets.get(person.session);
          if (!caret) {
            caret = document.createElement("span");
            caret.className = "kotoba-collab-caret";
            caret.append(document.createElement("span"));
            this.carets.set(person.session, caret);
          }
          // It glides to its new place, longer the farther it goes (a click across the page, an agent going to work).
          const left = parseFloat(caret.style.left);
          const top = parseFloat(caret.style.top);
          const distance = Number.isNaN(left) ? 0 : Math.hypot(rect.left - surface.left - left, rect.top - surface.top - top);
          caret.style.setProperty("--collab-caret-travel", `${Math.round(Math.min(400, Math.max(80, distance * 0.8)))}ms`);
          this.position(caret, rect, surface);
          caret.style.setProperty("--collab-color", this.color(person));
          const label = caret.firstElementChild as HTMLSpanElement;
          if (label.textContent !== person.user.name) label.textContent = person.user.name;
          label.style.backgroundColor = this.color(person);
          // Over the selections; never moved in the page, or it would not glide.
          if (caret.parentNode !== this.layer) this.layer.append(caret);
          drawn.add(person.session);
          if (this.room && following(this.room) === person.user.id) this.keepInView(person, rect);
        } catch { /* A DOM reconciliation can briefly detach an awareness anchor. */ }
      }
      for (const [session, caret] of this.carets) {
        if (drawn.has(session)) continue;
        caret.remove();
        this.carets.delete(session);
      }
      for (const session of this.wasCaret.keys()) if (!drawn.has(session)) this.wasCaret.delete(session);
    });
  }

  // The caret of the one followed stays on the screen, when no page of
  // Issho's (its pointers, of this room) keeps them there for the whole page.
  private keepInView(person: Person, rect: DOMRect): void {
    if (this.room && document.querySelector(`.issho-pointers[data-room="${CSS.escape(this.room)}"]`)) return;
    const where = JSON.stringify(person.selection);
    const height = document.documentElement.clientHeight;
    if (rect.top >= 0 && rect.bottom <= height) {
      this.scrolledTo = where;
      return;
    }
    if (this.scrolledTo === where) return;
    this.scrolledTo = where;
    const reduced = document.documentElement.dataset.isshoMotion === "reduced" || matchMedia("(prefers-reduced-motion: reduce)").matches;
    window.scrollBy({ top: rect.top + rect.height / 2 - height / 2, behavior: reduced ? "auto" : "smooth" });
  }

  /** Where a selection's end is in the viewport (its caret), or `null`: for Issho's pointers. */
  caretBox(selection: SharedSelection): DOMRect | null {
    const focus = this.binding.domPoint(selection.focus);
    try {
      return focus ? caretRect(focus) : null;
    } catch {
      return null;
    }
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
    this.lastSelections.clear();
    this.carets.clear();
    this.stopFollowing();
    this.wasCaret.clear();
    this.sweeps.clear();
    window.removeEventListener("scroll", this.onScroll, true);
    this.list.remove();
    this.layer.remove();
  }
}

function lineStart(node: Node): DOMRect | null {
  const element = node instanceof Element ? node : node.parentElement;
  if (!element) return null;
  const box = element.getBoundingClientRect();
  return new DOMRect(box.left, box.top, 0, box.height);
}

// The caret at a point: an empty line has no rectangle for a collapsed range, so the caret goes at the line's start.
function caretRect(focus: { node: Node; offset: number }): DOMRect | null {
  const range = document.createRange();
  range.setStart(focus.node, focus.offset);
  range.collapse(true);
  return range.getClientRects()[0] ?? lineStart(focus.node);
}

// A range's rectangles, one for each line: the slivers at the edges of its elements go into their line.
function lines(rects: DOMRect[]): DOMRect[] {
  const merged: DOMRect[] = [];
  for (const rect of rects) {
    const line = merged.find(other => Math.abs(other.top + other.height / 2 - (rect.top + rect.height / 2)) < Math.min(other.height, rect.height) / 2);
    if (!line) {
      merged.push(DOMRect.fromRect(rect));
      continue;
    }
    const left = Math.min(line.left, rect.left);
    const top = Math.min(line.top, rect.top);
    line.width = Math.max(line.right, rect.right) - left;
    line.height = Math.max(line.bottom, rect.bottom) - top;
    line.x = left;
    line.y = top;
  }
  return merged.sort((a, b) => a.top - b.top || a.left - b.left);
}
