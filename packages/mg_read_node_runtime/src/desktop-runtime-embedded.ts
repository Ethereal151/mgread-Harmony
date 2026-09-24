import type { PluginBrowserSessionProvider } from "./plugin-browser-session.js";
export { materializeTransferEmbedded } from "./embedded-transfer-materializer.js";

/** Creates the Android-hosted browser bridge when the embedded callback exists. */
export function createEmbeddedBrowserSession(): PluginBrowserSessionProvider | undefined {
  const request = (globalThis as {
    readonly __mgreadBrowserRequestJson?: (payload: string) => Promise<string>;
  }).__mgreadBrowserRequestJson;
  if (request === undefined) return undefined;
  return {
    request: async (value: unknown): Promise<unknown> =>
      JSON.parse(await request(JSON.stringify(value))),
  };
}
