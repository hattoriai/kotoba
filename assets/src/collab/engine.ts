import type { Applied, Engine, Operation as IsshoOperation, State as IsshoState } from "issho";
import { apply, type Operation, type State } from "./model";

/** The browser's twin of Kotoba.Issho.Engine: the same operations give the same document. */
export const kotobaEngine: Engine = {
  name: "kotoba",
  version: 1,
  apply(state: IsshoState, ops: IsshoOperation[]): Applied {
    try {
      return { ok: true, state: apply(state as unknown as State, ops as unknown as Operation[]) as unknown as IsshoState };
    } catch (error) {
      return { ok: false, reason: error instanceof Error ? error.message : "invalid_operation" };
    }
  },
};
