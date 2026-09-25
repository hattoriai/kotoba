import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

import { expect, test } from "@playwright/test";

const root = resolve(__dirname, "../..");

test("the package can be required and imported from Node", () => {
  const script = `
    const cjs = Object.keys(require("kotoba")).sort().join(",");
    import("kotoba").then((esm) => console.log(cjs + "|" + Object.keys(esm).sort().join(",")));
  `;
  const output = execFileSync(process.execPath, ["-e", script], {
    cwd: root,
    env: { ...process.env, NODE_PATH: resolve(root, "..") },
  });
  expect(output.toString().trim()).toBe("AttachmentNode,Kotoba,MentionNode|AttachmentNode,Kotoba,MentionNode");
});
