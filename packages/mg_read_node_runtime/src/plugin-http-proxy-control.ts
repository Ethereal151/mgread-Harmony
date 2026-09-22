/** Validates the app-owned proxy setting sent to the Runtime control plane. */
import type { RuntimeProtocolError, RuntimeRequest } from "./protocol.js";

export type PluginHttpProxyConfiguration =
  | { readonly proxyUrl: string | undefined; readonly noProxy?: string }
  | { readonly error: RuntimeProtocolError };

export function readPluginHttpProxyConfiguration(
  request: RuntimeRequest,
): PluginHttpProxyConfiguration {
  const keys = Object.keys(request.params);
  if (keys.some((key) => key !== "proxyUrl" && key !== "noProxy") || keys.length > 2 || !keys.includes("proxyUrl")) return invalid(request);
  const raw = request.params.proxyUrl;
  const noProxy = request.params.noProxy;
  if (noProxy !== undefined && (typeof noProxy !== "string" || Buffer.byteLength(noProxy, "utf8") > 2048)) return invalid(request);
  if (raw === null) return noProxy === undefined ? { proxyUrl: undefined } : { proxyUrl: undefined, noProxy };
  if (typeof raw !== "string" || Buffer.byteLength(raw, "utf8") > 2048) return invalid(request);
  try {
    const proxy = new URL(raw);
    if (
      !new Set(["http:", "https:", "socks5:"]).has(proxy.protocol) ||
      proxy.hostname === "" ||
      proxy.port === "" ||
      proxy.pathname !== "/" ||
      proxy.search !== "" ||
      proxy.hash !== ""
    ) return invalid(request);
    return noProxy === undefined ? { proxyUrl: proxy.href } : { proxyUrl: proxy.href, noProxy };
  } catch {
    return invalid(request);
  }
}

function invalid(request: RuntimeRequest): { readonly error: RuntimeProtocolError } {
  return {
    error: {
      code: "invalid_request",
      message: "The plugin HTTP proxy setting requires one HTTP, HTTPS or SOCKS5 proxy URL or null.",
      requestId: request.id,
      traceId: request.traceId,
    },
  };
}
