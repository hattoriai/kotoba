import { expect, test, type Page } from "@playwright/test";
import { focusEnd, openEditor } from "./support";

const editor = (page: Page) => page.locator("#shared_editor .kotoba-editable");
const caret = (page: Page) => page.locator("#shared_editor .kotoba-collab-caret");

async function open(page: Page, document: string, name: string): Promise<void> {
  await openEditor(page, `/collab?document=${document}&name=${name}`, "shared_editor");
  await expect(page.locator("[data-collab-status]")).toHaveText("Saved");
}

for (const sameAuthor of [true, false]) {
  for (const split of [false, true]) {
    test(`a cursor keeps its last known position before ${split ? "a new paragraph" : "new characters"} arrives (${sameAuthor ? "same author" : "different authors"})`, async ({ page, context, browser }) => {
      const otherContext = sameAuthor ? context : await browser.newContext();
      const other = await otherContext.newPage();
      let hold = false;
      let presence = 0;
      const queued: (() => void)[] = [];
      await other.routeWebSocket(/\/kotoba\/socket/, socket => {
        const server = socket.connectToServer();
        server.onMessage(message => {
          const [, , , event] = typeof message === "string" ? JSON.parse(message) as unknown[] : [];
          if (hold && event === "transaction") queued.push(() => socket.send(message));
          else {
            socket.send(message);
            if (event === "presence") presence++;
          }
        });
      });
      const id = crypto.randomUUID();
      await open(page, id, "Ada");
      await open(other, id, sameAuthor ? "Ada" : "Grace");
      await focusEnd(page, editor(page));
      await page.keyboard.type("abcdef");
      await expect(editor(other)).toHaveText("abcdef");
      await expect(caret(other)).toHaveCount(1);
      const end = await editor(other).evaluate(element => {
        const text = document.createTreeWalker(element.querySelector("p")!, NodeFilter.SHOW_TEXT).nextNode()!;
        const range = document.createRange();
        range.setStart(text, text.textContent!.length);
        range.collapse(true);
        return range.getBoundingClientRect().x;
      });
      await expect.poll(async () => (await caret(other).boundingBox())?.x ?? -1).toBeCloseTo(end, 0);
      const before = await caret(other).boundingBox();
      expect(before).not.toBeNull();
      const previousPresence = presence;
      hold = true;
      if (split) await page.keyboard.press("Enter");
      await page.keyboard.type("X");
      await expect.poll(() => queued.length).toBeGreaterThan(0);
      await expect.poll(() => presence).toBeGreaterThan(previousPresence);
      // Let the received awareness paint while the corresponding text is still withheld.
      await other.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
      await expect(caret(other)).toHaveCount(1);
      const waiting = await caret(other).boundingBox();
      expect(waiting!.x).toBeCloseTo(before!.x, 0);
      expect(waiting!.y).toBeCloseTo(before!.y, 0);
      hold = false;
      queued.splice(0).forEach(deliver => deliver());
      await expect(editor(other)).toHaveText("abcdefX");
      await expect.poll(async () => {
        const after = await caret(other).boundingBox();
        return after !== null && (split ? after.y > before!.y + 5 : after.x > before!.x + 2);
      }).toBe(true);
      if (!sameAuthor) await otherContext.close();
    });
  }
}
