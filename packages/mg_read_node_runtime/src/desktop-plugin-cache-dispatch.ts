/**
 * Runtime Core plugin storage control dispatch.
 *
 * Responsibilities:
 * - validate path-free cache and installation-usage requests;
 * - invoke the current PluginManager and project failures to wire errors.
 *
 * Boundaries:
 * - this module never exposes Runtime data paths;
 * - transport framing and manager lifecycle remain owned by DesktopRuntime.
 */
import type {
  RuntimeDispatchFailure,
  RuntimeDispatchResult,
  RuntimeRequestErrorFactory,
} from "./desktop-runtime-types.js";
import {
  isPluginManagerError,
  type PluginManager,
  PluginManagerError,
} from "./plugin-manager.js";
import { pluginManagerErrorMessage } from "./plugin-manager-error-message.js";
import type { RuntimeRequest } from "./protocol.js";

export type PluginStorageControlOperation =
  | "cacheUsage"
  | "installationUsage"
  | "cacheClear"
  | "cacheClearAll";

/** Dispatches one path-free plugin storage control operation. */
export async function dispatchPluginStorageControl(
  request: RuntimeRequest,
  manager: PluginManager | undefined,
  requestError: RuntimeRequestErrorFactory,
  operation: PluginStorageControlOperation,
): Promise<RuntimeDispatchResult> {
  switch (operation) {
    case "cacheUsage":
      return dispatchPluginCacheUsage(request, manager, requestError);
    case "installationUsage":
      return dispatchPluginInstallationUsage(request, manager, requestError);
    case "cacheClear":
      return dispatchPluginCacheClear(request, manager, requestError);
    case "cacheClearAll":
      return dispatchPluginCacheClearAll(request, manager, requestError);
  }
}

/** Returns only cache byte totals; cache paths remain Runtime-private. */
async function dispatchPluginCacheUsage(
  request: RuntimeRequest,
  manager: PluginManager | undefined,
  requestError: RuntimeRequestErrorFactory,
): Promise<RuntimeDispatchResult> {
  if (
    Object.keys(request.params).length > 1 ||
    (Object.keys(request.params).length === 1 && !("pluginId" in request.params)) ||
    (request.params.pluginId !== undefined && typeof request.params.pluginId !== "string")
  ) {
    return pluginCacheInvalidRequest(request, requestError);
  }
  try {
    if (manager === undefined) throw new PluginManagerError("plugin_load_failed");
    return {
      result: await manager.listCacheUsage(
        request.params.pluginId as string | undefined,
      ),
    };
  } catch (error) {
    return pluginCacheFailure(request, error, requestError);
  }
}

/** Returns retained archive and source data byte totals. */
async function dispatchPluginInstallationUsage(
  request: RuntimeRequest,
  manager: PluginManager | undefined,
  requestError: RuntimeRequestErrorFactory,
): Promise<RuntimeDispatchResult> {
  const pluginId = request.params.pluginId;
  const scope = request.params.scope;
  if (
    Object.keys(request.params).length !== 2 ||
    typeof pluginId !== "string" ||
    (scope !== "archive" && scope !== "data")
  ) {
    return {
      error: requestError(
        request,
        "invalid_request",
        "The installed source size request is invalid.",
      ),
    };
  }
  try {
    if (manager === undefined) throw new PluginManagerError("plugin_load_failed");
    return { result: await manager.measureInstallationUsage(pluginId, scope) };
  } catch (error) {
    return pluginCacheFailure(request, error, requestError);
  }
}

/** Clears one plugin cache and returns a terminal, path-free status. */
async function dispatchPluginCacheClear(
  request: RuntimeRequest,
  manager: PluginManager | undefined,
  requestError: RuntimeRequestErrorFactory,
): Promise<RuntimeDispatchResult> {
  if (
    Object.keys(request.params).length !== 1 ||
    typeof request.params.pluginId !== "string"
  ) {
    return pluginCacheInvalidRequest(request, requestError);
  }
  try {
    if (manager === undefined) throw new PluginManagerError("plugin_load_failed");
    return { result: await manager.clearPluginCache(request.params.pluginId) };
  } catch (error) {
    return pluginCacheFailure(request, error, requestError);
  }
}

/** Clears every installed plugin cache while retaining individual failures. */
async function dispatchPluginCacheClearAll(
  request: RuntimeRequest,
  manager: PluginManager | undefined,
  requestError: RuntimeRequestErrorFactory,
): Promise<RuntimeDispatchResult> {
  if (Object.keys(request.params).length !== 0) {
    return pluginCacheInvalidRequest(request, requestError);
  }
  try {
    if (manager === undefined) throw new PluginManagerError("plugin_load_failed");
    return { result: await manager.clearAllPluginCaches() };
  } catch (error) {
    return pluginCacheFailure(request, error, requestError);
  }
}

function pluginCacheInvalidRequest(
  request: RuntimeRequest,
  requestError: RuntimeRequestErrorFactory,
): RuntimeDispatchFailure {
  return {
    error: requestError(
      request,
      "invalid_request",
      "The plugin cache request is invalid.",
    ),
  };
}

function pluginCacheFailure(
  request: RuntimeRequest,
  error: unknown,
  requestError: RuntimeRequestErrorFactory,
): RuntimeDispatchFailure {
  if (isPluginManagerError(error)) {
    return {
      error: requestError(
        request,
        error.code,
        pluginManagerErrorMessage(error.code),
      ),
    };
  }
  return {
    error: requestError(
      request,
      "internal",
      "The plugin cache request could not be completed.",
    ),
  };
}
