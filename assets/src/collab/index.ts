// Import after the core bundle. The implementation uses that bundle's Lexical.
import type { registerCollaboration } from "../collaboration";
import { createCollaboration } from "./client";

export { createCollaboration } from "./client";
export { apply, envelope } from "./model";
export function enableCollaboration(register: typeof registerCollaboration): void { register(createCollaboration); }
