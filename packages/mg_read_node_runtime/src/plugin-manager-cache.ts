import { lstat, readdir, rm } from "node:fs/promises";
import { resolve } from "node:path";

import { PluginManagerError, type PluginCacheClearItem } from "./plugin-manager-contract.js";
import { isMissingPath } from "./plugin-manager-files.js";
import { PluginOperationCoordinator } from "./plugin-operation-coordinator.js";

function cacheDirectory(dataRoot: string, pluginId: string): string {
  return resolve(dataRoot, "plugin-cache", pluginId);
}

export async function cacheBytes(dataRoot: string, pluginId: string): Promise<number> {
  try {
    return await cacheBytesAt(cacheDirectory(dataRoot, pluginId));
  } catch (error) {
    if (isMissingPath(error)) return 0;
    throw error;
  }
}

async function cacheBytesAt(path: string): Promise<number> {
  const metadata = await lstat(path);
  if (!metadata.isDirectory()) return metadata.size;
  const entries = await readdir(path, { withFileTypes: true });
  let total = 0;
  for (const entry of entries) {
    total += await cacheBytesAt(resolve(path, entry.name));
    if (!Number.isSafeInteger(total)) throw new PluginManagerError("plugin_load_failed");
  }
  return total;
}

export async function clearPluginCache(
  dataRoot: string,
  operations: PluginOperationCoordinator,
  pluginId: string,
  signal: AbortSignal,
  deadlineUnixMs: string,
): Promise<PluginCacheClearItem> {
  let release: (() => void) | undefined;
  let bytesBefore = 0;
  try {
    release = await operations.acquireCacheClear(pluginId, signal, deadlineUnixMs);
    bytesBefore = await cacheBytes(dataRoot, pluginId);
    const directory = cacheDirectory(dataRoot, pluginId);
    let entries: string[];
    try {
      entries = await readdir(directory);
    } catch (error) {
      if (!isMissingPath(error)) throw error;
      entries = [];
    }
    await Promise.all(entries.map((entry) => rm(resolve(directory, entry), { force: true, recursive: true })));
    return Object.freeze({
      bytesBefore,
      bytesRemaining: await cacheBytes(dataRoot, pluginId),
      pluginId,
      status: "cleared",
    });
  } catch {
    let bytesRemaining = bytesBefore;
    try {
      bytesRemaining = await cacheBytes(dataRoot, pluginId);
    } catch {
      // The terminal status remains useful even if the failed directory cannot be read.
    }
    return Object.freeze({ bytesBefore, bytesRemaining, pluginId, status: "failed" });
  } finally {
    release?.();
  }
}
