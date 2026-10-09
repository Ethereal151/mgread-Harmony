/**
 * Runtime-private source-resource orchestration.
 *
 * Responsibilities:
 * - Own bounded HLS manifest warmup and live source-resource opening.
 * - Attach URL-free completion diagnostics to loopback responses.
 *
 * Notes:
 * - This is an internal data-plane owner and does not change the wire contract.
 * - Diagnostics contain only kind, role, status, timing, bytes, and header count.
 */
import type { JsonObject } from "./protocol.js";
import { HlsManifestWarmup, type HlsWarmupEvent } from "./hls-manifest-warmup.js";
import type { PluginManagerEventSink, PluginRuntimeHttpClient } from "./plugin-manager-contract.js";
import { openSourceProxyResource, type SourceProxyEntry, type SourceProxyResource } from "./source-resource-proxy.js";
import { decodeSourceResourceToken } from "./source-resource-token.js";

export class SourceResourceCoordinator {
  readonly #warmup: HlsManifestWarmup;
  readonly #http: PluginRuntimeHttpClient;
  readonly #events: PluginManagerEventSink;
  readonly #debugLogEnabled: () => boolean;
  readonly #resolveImage: (pluginId: string, request: JsonObject, signal: AbortSignal) => Promise<Response | undefined>;
  readonly #imageHandlerTails = new Map<string, Promise<void>>();

  constructor(
    http: PluginRuntimeHttpClient,
    events: PluginManagerEventSink,
    debugLogEnabled: () => boolean,
    resolveImage: (pluginId: string, request: JsonObject, signal: AbortSignal) => Promise<Response | undefined>,
  ) {
    this.#http = http;
    this.#events = events;
    this.#debugLogEnabled = debugLogEnabled;
    this.#resolveImage = resolveImage;
    this.#warmup = new HlsManifestWarmup((event) => this.#logWarmup(event));
  }

  created(pluginId: string, request: JsonObject, proxy: SourceProxyEntry["proxy"]): void {
    this.#warmup.schedule(pluginId, { fetch: this.#http.fetch.bind(this.#http), proxy, request });
    if (!this.#debugLogEnabled()) return;
    const headers = request.headers;
    const count = headers !== null && typeof headers === "object" && !Array.isArray(headers) ? Object.keys(headers).length : 0;
    this.#events({
      code: "plugin_log_emitted", logCategory: "runtime.plugin.resource_proxy", logLevel: "debug",
      logMessage: `资源代理已创建：类型=${String(request.kind)}，角色=${String(request.resourceRole ?? "root")}，请求头数量=${count}`,
      outcome: "success", pluginId,
    });
  }

  async open(
    token: string,
    requestHeaders: Readonly<Record<string, string>>,
    signal: AbortSignal,
    proxy: (pluginId: string, request: JsonObject) => string,
  ): Promise<SourceProxyResource | undefined> {
    const decoded = decodeSourceResourceToken(token);
    if (decoded === undefined) return openSourceProxyResource(undefined, requestHeaders, signal);
    if (decoded.request.handler !== undefined) {
      if (decoded.request.kind !== "image" || typeof decoded.request.handler !== "string" ||
          !/^[a-z][a-z0-9-]{0,63}$/u.test(decoded.request.handler)) return undefined;
      // The OHOS device receives the current Baozimh CDN hostname in the
      // descriptor, while that installed handler's own canonicalizer accepts
      // the s1.bzcdn.net alias. Normalize only this proven platform boundary
      // before invoking the handler; do not alter the source artifact or
      // silently fall back to an ordinary upstream fetch.
      const request = normalizeBaozimhSourceResourceRequest(decoded.request);
      if (this.#debugLogEnabled()) {
        this.#events({
          code: "plugin_log_emitted", logCategory: "runtime.plugin.resource_proxy", logLevel: "debug",
          logMessage: `资源处理器请求：处理器=${String(request.handler)}，地址=${String(request.url)}`,
          outcome: "started", pluginId: decoded.pluginId,
        });
      }
      // A handler may implement one image request as a multi-step browser
      // transaction (restore Referer page, navigate to the image, then fetch).
      // Keep that transaction intact per plugin; the page capability itself is
      // intentionally shared for ordinary source work.
      const response = await this.#resolveImageSerially(decoded.pluginId, request, signal);
      if (response === undefined) return undefined;
      return Object.freeze({
        proxy: (request: JsonObject) => proxy(decoded.pluginId, request),
        request,
        response,
        responseUrl: typeof request.url === "string" ? request.url : "",
      });
    }
    const entry: SourceProxyEntry = {
      fetch: this.#http.fetch.bind(this.#http),
      proxy: (request) => proxy(decoded.pluginId, request),
      request: decoded.request,
    };
    const resource = await this.#warmup.open(decoded.pluginId, entry, requestHeaders, signal);
    if (resource === undefined) return undefined;
    return Object.freeze({
      ...resource,
      onServed: (status: number, bytes: number, durationMs: number) => {
        if (!this.#debugLogEnabled()) return;
        this.#events({
          code: "plugin_log_emitted", logCategory: "runtime.plugin.resource_proxy",
          logLevel: status >= 400 ? "warn" : "debug",
          logMessage: `资源代理响应：类型=${String(decoded.request.kind)}，角色=${String(decoded.request.resourceRole ?? "root")}，状态=${status}，耗时毫秒=${Math.round(durationMs)}，字节=${bytes}`,
          outcome: status >= 400 ? "error" : "success", pluginId: decoded.pluginId,
        });
      },
    });
  }

  #logWarmup(event: HlsWarmupEvent): void {
    if (!this.#debugLogEnabled()) return;
    this.#events({
      code: "plugin_log_emitted", logCategory: "runtime.plugin.resource_proxy",
      logLevel: event.phase === "failed" ? "warn" : "debug",
      logMessage: `HLS清单预热：阶段=${event.phase}，角色=${event.resourceRole}，耗时毫秒=${event.durationMs}${event.bytes === undefined ? "" : `，字节=${event.bytes}`}`,
      outcome: event.phase === "failed" ? "error" : event.phase === "started" ? "started" : "success",
      pluginId: event.pluginId,
    });
  }

  async #resolveImageSerially(
    pluginId: string,
    request: JsonObject,
    signal: AbortSignal,
  ): Promise<Response | undefined> {
    let release: () => void = (): void => {};
    const turn = new Promise<void>((resolve): void => {
      release = resolve;
    });
    const previous = this.#imageHandlerTails.get(pluginId) ?? Promise.resolve();
    const tail = previous.then((): Promise<void> => turn);
    this.#imageHandlerTails.set(pluginId, tail);
    await previous;
    try {
      return await this.#resolveImage(pluginId, request, signal);
    } finally {
      release();
      if (this.#imageHandlerTails.get(pluginId) === tail) this.#imageHandlerTails.delete(pluginId);
    }
  }
}

/**
 * Bridges the current Baozimh CDN and Referer aliases to the aliases already
 * accepted by its installed image handler. The mapping is deliberately exact;
 * other handlers and URLs keep their descriptors unchanged.
 */
export function normalizeBaozimhSourceResourceRequest(request: JsonObject): JsonObject {
  if (request.handler !== "baozimh-image-v1" || typeof request.url !== "string" ||
      !isJsonObject(request.params)) return request;
  let url: URL;
  try {
    url = new URL(request.url);
  } catch {
    return request;
  }
  if (url.protocol !== "https:" || request.params.origin !== url.origin ||
      request.params.path !== url.pathname) return request;
  const decoratedCdn = /^(s[12])(?:-[a-z0-9-]+)*\.bzcdn\.net$/u.exec(url.hostname);
  if (url.hostname === "static-tw.bzmgcn.com") {
    url.hostname = "s1.bzcdn.net";
  } else if (decoratedCdn !== null && url.hostname !== `${decoratedCdn[1]}.bzcdn.net`) {
    url.hostname = `${decoratedCdn[1]}.bzcdn.net`;
  } else if (decoratedCdn === null) {
    return request;
  }
  const headers = isJsonObject(request.headers) ? request.headers : undefined;
  const refererKey = headers !== undefined && typeof headers.Referer === "string"
    ? "Referer"
    : headers !== undefined && typeof headers.referer === "string"
    ? "referer"
    : undefined;
  let normalizedHeaders = headers;
  const refererValue = refererKey === undefined || headers === undefined ? undefined : headers[refererKey];
  if (refererKey !== undefined && typeof refererValue === "string") {
    try {
      const referer = new URL(refererValue);
      if (referer.protocol === "https:" &&
          (referer.hostname === "cn.bzmgcn.com" || referer.hostname === "cn.cnbzmg.com")) {
        referer.hostname = "www.baozimh.com";
        normalizedHeaders = Object.freeze({ ...headers, [refererKey]: referer.toString() });
      }
    } catch {
      // The installed handler will keep reporting its own invalid Referer.
    }
  }
  return Object.freeze({
    ...request,
    url: url.toString(),
    params: Object.freeze({ ...request.params, origin: url.origin, path: url.pathname }),
    ...(normalizedHeaders === undefined ? {} : { headers: normalizedHeaders }),
  });
}

function isJsonObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
