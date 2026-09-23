import { resolve } from "node:path";

import type { DevelopmentPluginRegistry } from "./development-plugin-registry.js";
import { exists, isPluginId } from "./plugin-manager-files.js";
import {
  createDevelopmentPackageArtifactResource,
  listExportablePluginArtifacts,
  listPluginTransferOffers as buildPluginTransferOffers,
  toDevelopmentTransferProject,
} from "./plugin-manager-artifact-transfer.js";
import {
  PluginManagerError,
  type InstalledPluginSnapshot,
  type LoadedPlugin,
  type PluginCacheClearItem,
  type PluginCacheClearResult,
  type PluginCacheUsage,
  type PluginCodeDirectory,
  type PluginInstallationUsage,
  type PluginIconResource,
  type PluginManagerEventSink,
  type PluginUninstallAllResult,
  type PluginUninstallResult,
} from "./plugin-manager-contract.js";
import { InstalledPluginCatalog } from "./plugin-catalog.js";
import { PluginIconResources } from "./plugin-icon-resources.js";
import { measureInstallationTree, retainedArtifactPath } from "./plugin-installation-usage.js";
import { PluginInstaller } from "./plugin-installer.js";
import { PluginOperationCoordinator } from "./plugin-operation-coordinator.js";
import type {
  PluginTransferArtifact,
  PluginTransferOffer,
  PluginTransferPlanItem,
  PluginTransferResource,
} from "./plugin-artifact-transfer.js";
import { PluginArtifactTransferManager } from "./plugin-artifact-transfer.js";

const DEFAULT_UNINSTALL_CONCURRENCY = 4;
const EMBEDDED_UNINSTALL_CONCURRENCY = 2;

export interface PluginManagerMaintenanceContext {
  readonly dataRoot: string;
  readonly embedded: boolean;
  readonly development: DevelopmentPluginRegistry;
  readonly events: PluginManagerEventSink;
  readonly catalog: InstalledPluginCatalog;
  readonly installer: PluginInstaller;
  readonly pluginIcons: PluginIconResources;
  readonly resourceOrigin: () => string;
  readonly pluginOperations: PluginOperationCoordinator;
  readonly pluginTransfer: PluginArtifactTransferManager;
  readonly cacheClearTimeoutMs: number;
  readonly initialize: () => Promise<void>;
  readonly snapshots: () => readonly InstalledPluginSnapshot[];
  readonly combinedSnapshots: () => readonly InstalledPluginSnapshot[];
  readonly setSnapshots: (snapshots: readonly InstalledPluginSnapshot[]) => void;
  readonly installedLoaded: Map<string, LoadedPlugin>;
  readonly installedLoadPromises: Map<string, Promise<LoadedPlugin>>;
  readonly cacheBytes: (pluginId: string) => Promise<number>;
  readonly clearCache: (
    pluginId: string,
    signal: AbortSignal,
    deadlineUnixMs: string,
  ) => Promise<PluginCacheClearItem>;
  readonly reportUninstallProgress: (
    code: "plugin_uninstall_started" | "plugin_uninstall_completed",
    snapshot: InstalledPluginSnapshot,
    itemCount: number,
    totalItemCount: number,
  ) => void;
}

export async function listExportableArtifacts(
  context: PluginManagerMaintenanceContext,
): Promise<readonly PluginTransferArtifact[]> {
  await context.initialize();
  await context.development.ensureAllLoaded();
  return listExportablePluginArtifacts(
    context.pluginTransfer,
    context.snapshots(),
    context.development.loadedValues(),
  );
}

export async function listPluginTransferOffers(
  context: PluginManagerMaintenanceContext,
): Promise<readonly PluginTransferOffer[]> {
  await context.initialize();
  await context.development.ensureAllLoaded();
  return buildPluginTransferOffers(
    context.pluginTransfer,
    context.snapshots(),
    context.development.loadedValues(),
  );
}

export async function planPluginTransfer(
  context: PluginManagerMaintenanceContext,
  incoming: readonly PluginTransferArtifact[],
  forceUpgradeIds: ReadonlySet<string>,
): Promise<readonly PluginTransferPlanItem[]> {
  await context.initialize();
  await context.development.ensureAllLoaded();
  const development = [...context.development.loadedValues()].map((plugin) => ({
    fingerprint: plugin.fingerprint,
    id: plugin.loaded.descriptor.id,
    syncRevision: plugin.syncRevision,
  }));
  return context.pluginTransfer.plan(incoming, context.combinedSnapshots(), development, forceUpgradeIds);
}

export async function planPluginTransferOffers(
  context: PluginManagerMaintenanceContext,
  incoming: readonly PluginTransferOffer[],
  forceUpgradeIds: ReadonlySet<string>,
): Promise<readonly PluginTransferPlanItem[]> {
  await context.initialize();
  await context.development.ensureAllLoaded();
  const development = [...context.development.loadedValues()].map((plugin) => ({
    fingerprint: plugin.fingerprint,
    id: plugin.loaded.descriptor.id,
    syncRevision: plugin.syncRevision,
  }));
  return context.pluginTransfer.planOffers(incoming, context.combinedSnapshots(), development, forceUpgradeIds);
}

export async function createPluginTransferResource(
  context: PluginManagerMaintenanceContext,
  id: string,
  version: string,
): Promise<{ readonly token: string; readonly artifact: PluginTransferArtifact }> {
  await context.initialize();
  const development = await context.development.ensureLoaded(id);
  return context.pluginTransfer.createResource(
    id,
    version,
    development === undefined ? undefined : toDevelopmentTransferProject(development),
  );
}

export async function createDevelopmentPackageResource(
  context: PluginManagerMaintenanceContext,
  pluginId: string,
): Promise<{ readonly artifact: PluginTransferArtifact; readonly fileName: string; readonly token: string }> {
  await context.initialize();
  if (!isPluginId(pluginId)) throw new PluginManagerError("invalid_request");
  const development = await context.development.ensureLoaded(pluginId);
  if (development === undefined) throw new PluginManagerError("plugin_not_found");
  return createDevelopmentPackageArtifactResource(context.pluginTransfer, development);
}

export function verifyPluginTransferInbox(
  context: PluginManagerMaintenanceContext,
  incoming: readonly PluginTransferArtifact[],
): Promise<void> {
  return context.pluginTransfer.verifyInbox(incoming);
}

export function consumePluginTransferResource(
  context: PluginManagerMaintenanceContext,
  token: string,
): PluginTransferResource | undefined {
  return context.pluginTransfer.consumeResource(token);
}

export function consumePluginIconResource(
  context: PluginManagerMaintenanceContext,
  token: string,
): Promise<PluginIconResource | undefined> {
  return context.pluginIcons.consume(token);
}

export async function resolveCodeDirectory(
  context: PluginManagerMaintenanceContext,
  pluginId: string,
): Promise<PluginCodeDirectory> {
  await context.initialize();
  if (!isPluginId(pluginId)) throw new PluginManagerError("invalid_request");
  const development = context.development.project(pluginId);
  if (development !== undefined) return Object.freeze({ directory: development.projectRoot, kind: "development" });
  const snapshot = context.snapshots().find((item) => item.id === pluginId);
  if (snapshot === undefined) throw new PluginManagerError("plugin_not_found");
  const version = snapshot.activeVersion ?? snapshot.pendingVersion;
  if (version === null) throw new PluginManagerError("plugin_load_failed");
  const directory = resolve(context.dataRoot, "plugins", pluginId, "versions", version);
  if (!await exists(directory)) throw new PluginManagerError("plugin_load_failed");
  return Object.freeze({ directory, kind: "installed" });
}

export async function listCacheUsage(
  context: PluginManagerMaintenanceContext,
  pluginId?: string,
): Promise<readonly PluginCacheUsage[]> {
  await context.initialize();
  const selected = context.combinedSnapshots().filter((snapshot) => pluginId === undefined || snapshot.id === pluginId);
  return Object.freeze(await Promise.all(selected.map(async (snapshot) => Object.freeze({
    bytes: await context.cacheBytes(snapshot.id),
    pluginId: snapshot.id,
  }))));
}

export async function measureInstallationUsage(
  context: PluginManagerMaintenanceContext,
  pluginId: string,
  scope: "archive" | "data" | "npm",
): Promise<PluginInstallationUsage> {
  await context.initialize();
  if (!isPluginId(pluginId) || (scope !== "archive" && scope !== "data" && scope !== "npm")) {
    throw new PluginManagerError("invalid_request");
  }
  const snapshot = context.snapshots().find((item) => item.id === pluginId);
  if (snapshot === undefined) throw new PluginManagerError("plugin_not_found");
  const version = snapshot.activeVersion ?? snapshot.pendingVersion;
  if (version === null) throw new PluginManagerError("plugin_load_failed");
  const versionRoot = resolve(context.dataRoot, "plugins", pluginId, "versions", version);
  const root = scope === "archive"
    ? await retainedArtifactPath(context.dataRoot, pluginId, version)
    : scope === "npm" ? resolve(versionRoot, "node_modules") : versionRoot;
  const result = await measureInstallationTree(root, scope);
  return Object.freeze({ bytes: result.bytes, fileCount: result.fileCount, pluginId, scope, version });
}

export async function clearPluginCache(
  context: PluginManagerMaintenanceContext,
  pluginId: string,
  signal?: AbortSignal,
  deadlineUnixMs?: string,
): Promise<PluginCacheClearResult> {
  await context.initialize();
  if (!isPluginId(pluginId)) throw new PluginManagerError("invalid_request");
  if (!context.combinedSnapshots().some((item) => item.id === pluginId)) throw new PluginManagerError("plugin_not_found");
  const cancellation = signal ?? new AbortController().signal;
  const deadline = deadlineUnixMs ?? String(Date.now() + context.cacheClearTimeoutMs);
  return Object.freeze({ items: Object.freeze([await context.clearCache(pluginId, cancellation, deadline)]) });
}

export async function clearAllPluginCaches(
  context: PluginManagerMaintenanceContext,
  signal?: AbortSignal,
  deadlineUnixMs?: string,
): Promise<PluginCacheClearResult> {
  await context.initialize();
  const pluginIds = context.combinedSnapshots().map((item) => item.id);
  const cancellation = signal ?? new AbortController().signal;
  const deadline = deadlineUnixMs ?? String(Date.now() + context.cacheClearTimeoutMs);
  return Object.freeze({
    items: Object.freeze(await Promise.all(pluginIds.map((pluginId) => context.clearCache(pluginId, cancellation, deadline)))),
  });
}

export async function setEnabled(
  context: PluginManagerMaintenanceContext,
  pluginId: string,
  enabled: boolean,
): Promise<InstalledPluginSnapshot> {
  await context.initialize();
  if (!isPluginId(pluginId) || context.development.has(pluginId)) throw new PluginManagerError("invalid_request");
  const snapshots = context.snapshots();
  const index = snapshots.findIndex((item) => item.id === pluginId);
  if (index < 0) throw new PluginManagerError("plugin_not_found");
  const record = await context.catalog.setEnabled(pluginId, enabled);
  if (record === undefined) throw new PluginManagerError("plugin_not_found");
  const updated = record.snapshot;
  context.setSnapshots(Object.freeze([...snapshots.slice(0, index), updated, ...snapshots.slice(index + 1)]));
  context.events({ code: enabled ? "plugin_enabled" : "plugin_disabled", outcome: "success", pluginId });
  return context.pluginIcons.project(updated, context.development.projects(), context.resourceOrigin());
}

export async function uninstall(
  context: PluginManagerMaintenanceContext,
  pluginId: string,
  signal?: AbortSignal,
  deadlineUnixMs?: string,
): Promise<PluginUninstallResult> {
  await context.initialize();
  if (!isPluginId(pluginId) || context.development.has(pluginId)) throw new PluginManagerError("invalid_request");
  const snapshot = context.snapshots().find((item) => item.id === pluginId);
  if (snapshot === undefined) throw new PluginManagerError("plugin_not_found");
  context.reportUninstallProgress("plugin_uninstall_started", snapshot, 0, 1);
  await uninstallInstalled(context, pluginId, signal, deadlineUnixMs);
  context.reportUninstallProgress("plugin_uninstall_completed", snapshot, 1, 1);
  return Object.freeze({ pluginId, removed: true });
}

export async function uninstallAll(
  context: PluginManagerMaintenanceContext,
  signal?: AbortSignal,
  deadlineUnixMs?: string,
): Promise<PluginUninstallAllResult> {
  await context.initialize();
  const snapshots = context.snapshots();
  let completedCount = 0;
  await mapWithConcurrency(
    snapshots,
    context.embedded ? EMBEDDED_UNINSTALL_CONCURRENCY : DEFAULT_UNINSTALL_CONCURRENCY,
    async (snapshot) => {
      context.reportUninstallProgress("plugin_uninstall_started", snapshot, completedCount, snapshots.length);
      await uninstallInstalled(context, snapshot.id, signal, deadlineUnixMs, false);
      completedCount += 1;
      context.reportUninstallProgress("plugin_uninstall_completed", snapshot, completedCount, snapshots.length);
    },
  );
  await context.installer.collectUnusedDependencies();
  return Object.freeze({ removedCount: snapshots.length });
}

async function uninstallInstalled(
  context: PluginManagerMaintenanceContext,
  pluginId: string,
  signal?: AbortSignal,
  deadlineUnixMs?: string,
  collectUnusedDependencies = true,
): Promise<void> {
  const cancellation = signal ?? new AbortController().signal;
  const deadline = deadlineUnixMs ?? String(Date.now() + context.cacheClearTimeoutMs);
  const release = await context.pluginOperations.acquireCacheClear(pluginId, cancellation, deadline);
  try {
    await context.catalog.remove(pluginId);
    if (collectUnusedDependencies) await context.installer.collectUnusedDependencies();
    context.installedLoaded.delete(pluginId);
    context.installedLoadPromises.delete(pluginId);
    context.setSnapshots(Object.freeze(context.snapshots().filter((item) => item.id !== pluginId)));
  } finally {
    release();
  }
}

async function mapWithConcurrency<T>(
  inputs: readonly T[],
  concurrency: number,
  operation: (input: T) => Promise<void>,
): Promise<void> {
  let cursor = 0;
  const workers = Array.from({ length: Math.min(concurrency, inputs.length) }, async () => {
    while (cursor < inputs.length) {
      const index = cursor++;
      await operation(inputs[index]!);
    }
  });
  await Promise.all(workers);
}
