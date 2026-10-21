// The part of Phoenix's client that Issho's transport uses (Kotoba does not
// bundle Phoenix: the application has it).
declare module "phoenix" {
  type Payload = any;
  export interface Push { receive(status: "ok" | "error" | "timeout", callback: (payload: Payload) => void): Push }
  export interface Channel {
    join(timeout?: number): Push;
    leave(): Push;
    push(event: string, payload: object, timeout?: number): Push;
    on(event: string, callback: (payload: Payload) => void): number;
    onError(callback: () => void): void;
    onClose(callback: () => void): void;
  }
  export class Socket {
    constructor(url: string, options?: Record<string, unknown>);
    connect(): void;
    disconnect(callback?: () => void): void;
    ping(callback: (rtt: number) => void): boolean;
    onOpen(callback: () => void): string;
    onClose(callback: () => void): string;
    channel(topic: string, params: Record<string, unknown> | (() => Record<string, unknown>)): Channel;
  }
}
