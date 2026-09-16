import { copyFile } from "node:fs/promises";

import type { JsonValue, RuntimeProtocolError } from "./protocol.js";
import type { PluginManager } from "./plugin-manager.js";

export type EmbeddedTransferResult =
  | { readonly ok: true; readonly result: JsonValue }
  | { readonly error: RuntimeProtocolError; readonly ok: false };

export async function materializeTransferEmbedded(
  pluginManager: PluginManager | undefined,
  token: string,
  destination: string,
): Promise<EmbeddedTransferResult> {
  const resource = pluginManager?.consumePluginTransferResource(token);
  if (resource === undefined) {
    return { ok: false, error: {
      code: "plugin_transfer_artifact_missing",
      message: "The Runtime transfer artifact is unavailable.",
      requestId: undefined,
      traceId: undefined,
    } };
  }
  try {
    await copyFile(resource.path, destination);
    return { ok: true, result: { bytes: resource.bytes, checksum: resource.checksum } };
  } catch {
    return { ok: false, error: {
      code: "internal",
      message: "The Runtime transfer artifact could not be materialized.",
      requestId: undefined,
      traceId: undefined,
    } };
  }
}
