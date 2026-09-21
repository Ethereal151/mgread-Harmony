/**
 * Runtime-owned HTTP client used only by the public `ctx.http.fetch` API.
 *
 * Responsibilities:
 * - follow Node's system/environment proxy by default while allowing HTTP/2
 *   negotiation with transparent HTTP/1.1 fallback;
 * - route plugin HTTP and Runtime source-resource requests directly through
 *   one explicitly configured upstream proxy with the same negotiation;
 * - supply the Runtime-owned reduced desktop Chrome user-agent unless a
 *   source explicitly overrides it;
 * - switch future requests without mutating process environment or global fetch.
 *
 * Notes:
 * - the app supplies the upstream HTTP, HTTPS or SOCKS5 URL;
 * - existing requests retain the dispatcher sampled when they started.
 */
import {
  Agent,
  EnvHttpProxyAgent,
  ProxyAgent,
  Socks5ProxyAgent,
  type Dispatcher,
} from "undici";
import { Agent as HttpAgent, request as httpRequest, type ClientRequest } from "node:http";
import { Agent as HttpsAgent, request as httpsRequest } from "node:https";
import { connect as netConnect } from "node:net";
import type { Duplex } from "node:stream";
import { connect as tlsConnect } from "node:tls";
import { createBrotliDecompress, createGunzip, createInflate } from "node:zlib";

import type {
  PluginRuntimeHttpClient,
  PluginRuntimeHttpProxyMode,
  PluginRuntimeTraceContext,
} from "./plugin-manager-contract.js";

/** Chrome Stable 152.0.7977.64 reduced desktop UA, verified on 2026-08-31. */
export const defaultPluginUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36";

const http2TlsOptions = Object.freeze({ allowH2: true as const });

type Socks5Http2Options = NonNullable<ConstructorParameters<typeof Socks5ProxyAgent>[1]> & {
  readonly requestTls: {
    readonly ALPNProtocols: readonly ["h2", "http/1.1"];
  };
};
const socks5Http2Options: Socks5Http2Options = Object.freeze({
  requestTls: Object.freeze({ ALPNProtocols: ["h2", "http/1.1"] as const }),
});

export interface PluginHttpEnvironmentProxyOptions {
  readonly httpProxy?: string;
  readonly httpsProxy?: string;
  readonly noProxy?: string;
}

export class ConfigurablePluginHttpClient implements PluginRuntimeHttpClient {
  readonly #directAgent: Dispatcher;
  readonly #systemProxyAgent: Dispatcher;
  #proxyAgent: Dispatcher | undefined;
  #proxyUrl: string | undefined;
  readonly #retiring = new Set<Promise<void>>();

  constructor(environmentProxy: PluginHttpEnvironmentProxyOptions = {}) {
    this.#directAgent = new Agent(http2TlsOptions);
    this.#systemProxyAgent = new EnvHttpProxyAgent({
      allowH2: true,
      requestTls: http2TlsOptions,
      ...environmentProxy,
    });
  }

  configure(proxyUrl: string | undefined): void {
    if (this.#proxyUrl === proxyUrl) return;
    const next = proxyUrl === undefined
      ? undefined
      : proxyUrl.startsWith("socks5:")
        ? new Socks5ProxyAgent(proxyUrl, socks5Http2Options)
        : new ProxyAgent({
            allowH2: true,
            requestTls: http2TlsOptions,
            uri: proxyUrl,
          });
    const previous = this.#proxyAgent;
    this.#proxyAgent = next;
    this.#proxyUrl = proxyUrl;
    if (previous !== undefined) this.#retire(previous);
  }

  fetch(
    input: string | URL,
    init: RequestInit,
    _trace?: PluginRuntimeTraceContext,
    proxyMode?: PluginRuntimeHttpProxyMode,
  ): Promise<Response> {
    const requestInit = withDefaultUserAgent(init);
    // HarmonyOS runs the embedded Node host with --jitless because its W^X
    // policy rejects V8's executable JIT range. That build also omits the
    // WebAssembly global, while Undici's llhttp parser requires it. Keep the
    // public fetch contract alive with Node's native HTTP parser on that
    // platform; desktop and Android retain the negotiated Undici path.
    if ((globalThis as { readonly WebAssembly?: unknown }).WebAssembly === undefined) {
      return fetchWithoutWebAssembly(input, requestInit, 0, proxyMode === "direct" ? undefined : this.#proxyUrl);
    }
    const dispatcher = proxyMode === "direct"
      ? this.#directAgent
      : this.#proxyAgent ?? this.#systemProxyAgent;
    const proxiedInit = { ...requestInit, dispatcher } as RequestInit & { readonly dispatcher: Dispatcher };
    return fetch(input, proxiedInit);
  }

  async close(): Promise<void> {
    const current = this.#proxyAgent;
    this.#proxyAgent = undefined;
    this.#proxyUrl = undefined;
    if (current !== undefined) this.#retire(current);
    this.#retire(this.#directAgent);
    this.#retire(this.#systemProxyAgent);
    await Promise.allSettled([...this.#retiring]);
  }

  #retire(agent: Dispatcher): void {
    let operation: Promise<void>;
    operation = agent.close().catch(() => {}).finally(() => this.#retiring.delete(operation));
    this.#retiring.add(operation);
  }
}

const fallbackMaximumRedirects = 10;

function fetchWithoutWebAssembly(
  input: string | URL,
  init: RequestInit,
  redirectCount = 0,
  proxyUrl?: string,
): Promise<Response> {
  const url = new URL(input.toString());
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return Promise.reject(new TypeError(`Unsupported URL protocol: ${url.protocol}`));
  }
  const method = (init.method ?? "GET").toUpperCase();
  const headers = new Headers(init.headers);
  const body = fallbackRequestBody(init.body);
  if (body !== undefined && !headers.has("content-length")) headers.set("content-length", String(body.byteLength));

  return new Promise<Response>((resolve, reject) => {
    let settled = false;
    let request: ClientRequest | undefined;
    const finish = <T>(callback: (value: T) => void, value: T): void => {
      if (settled) return;
      settled = true;
      init.signal?.removeEventListener("abort", onAbort);
      callback(value);
    };
    const onAbort = (): void => {
      request?.destroy();
      finish(reject, new DOMException("The operation was aborted.", "AbortError"));
    };
    if (init.signal?.aborted) {
      onAbort();
      return;
    }

    const proxy = proxyUrl === undefined ? undefined : parseFallbackProxy(proxyUrl);
    const transport = createFallbackTransport(url, proxy, headers, method);
    request = transport.request((response) => {
      const chunks: Buffer[] = [];
      const contentEncoding = (String(response.headers["content-encoding"] ?? "").split(",", 1)[0] ?? "").trim().toLowerCase();
      const decoded = contentEncoding === "gzip"
        ? response.pipe(createGunzip())
        : contentEncoding === "deflate"
          ? response.pipe(createInflate())
          : contentEncoding === "br"
            ? response.pipe(createBrotliDecompress())
            : response;
      decoded.on("data", (chunk: Buffer | string) => chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)));
      decoded.once("error", (error) => finish(reject, error));
      decoded.once("end", () => {
        const status = response.statusCode ?? 0;
        const location = response.headers.location;
        if (location !== undefined && status >= 300 && status < 400 && init.redirect !== "manual") {
          if (init.redirect === "error" || redirectCount >= fallbackMaximumRedirects) {
            finish(reject, new TypeError("The HTTP redirect limit was exceeded."));
            return;
          }
          let nextInit: RequestInit = { ...init, headers };
          if (status === 301 || status === 302 || status === 303) {
            nextInit = { ...nextInit, method: "GET", body: null };
          }
          fetchWithoutWebAssembly(new URL(location, url), nextInit, redirectCount + 1, proxyUrl).then(
            (value) => finish(resolve, value),
            (error: unknown) => finish(reject, error),
          );
          return;
        }
        const responseHeaders = new Headers();
        for (const [name, value] of Object.entries(response.headers)) {
          if (value === undefined) continue;
          if (name === "content-encoding" || name === "content-length") continue;
          responseHeaders.set(name, Array.isArray(value) ? value.join(", ") : value);
        }
        finish(resolve, new Response(Buffer.concat(chunks), { status, headers: responseHeaders }));
      });
    });
    init.signal?.addEventListener("abort", onAbort, { once: true });
    request.once("error", (error) => finish(reject, error));
    if (body !== undefined) request.write(body);
    request.end();
  });
}

type FallbackProxy = {
  readonly url: URL;
  readonly usernamePassword?: string;
};

type FallbackTransport = {
  readonly request: (callback: (response: import("node:http").IncomingMessage) => void) => ClientRequest;
};

function parseFallbackProxy(proxyUrl: string): FallbackProxy {
  const url = new URL(proxyUrl);
  if (url.protocol !== "http:" && url.protocol !== "https:" && url.protocol !== "socks5:") {
    throw new TypeError(`The no-WebAssembly HTTP fallback does not support proxy protocol ${url.protocol}`);
  }
  const usernamePassword = url.username.length === 0 && url.password.length === 0
    ? undefined
    : `Basic ${Buffer.from(`${decodeURIComponent(url.username)}:${decodeURIComponent(url.password)}`).toString("base64")}`;
  url.username = "";
  url.password = "";
  return usernamePassword === undefined ? { url } : { url, usernamePassword };
}

function createFallbackTransport(url: URL, proxy: FallbackProxy | undefined, headers: Headers, method: string): FallbackTransport {
  const targetHeaders = Object.fromEntries(headers.entries());
  if (proxy === undefined) {
    return {
      request: (callback) => (url.protocol === "https:" ? httpsRequest : httpRequest)({
        protocol: url.protocol,
        hostname: url.hostname,
        ...(url.port.length === 0 ? {} : { port: Number(url.port) }),
        path: `${url.pathname || "/"}${url.search}`,
        method,
        headers: targetHeaders,
      }, callback),
    };
  }
  if (proxy.url.protocol === "socks5:") {
    const agent = url.protocol === "https:"
      ? new Socks5FallbackAgent(proxy.url)
      : new Socks5HttpFallbackAgent(proxy.url);
    return {
      request: (callback) => (url.protocol === "https:" ? httpsRequest : httpRequest)({
        protocol: url.protocol,
        hostname: url.hostname,
        ...(url.port.length === 0 ? {} : { port: Number(url.port) }),
        path: `${url.pathname || "/"}${url.search}`,
        method,
        headers: targetHeaders,
        agent,
      }, callback),
    };
  }
  if (url.protocol === "http:") {
    const proxyHeaders = { ...targetHeaders };
    if (proxyHeaders.host === undefined) proxyHeaders.host = url.host;
    if (proxy.usernamePassword !== undefined) proxyHeaders["proxy-authorization"] = proxy.usernamePassword;
    return {
      request: (callback) => (proxy.url.protocol === "https:" ? httpsRequest : httpRequest)({
        protocol: proxy.url.protocol,
        hostname: proxy.url.hostname,
        ...(proxy.url.port.length === 0 ? {} : { port: Number(proxy.url.port) }),
        path: url.toString(),
        method,
        headers: proxyHeaders,
      }, callback),
    };
  }
  const agent = new HttpConnectFallbackAgent(proxy.url, proxy.usernamePassword);
  return {
    request: (callback) => httpsRequest({
      protocol: url.protocol,
      hostname: url.hostname,
      ...(url.port.length === 0 ? {} : { port: Number(url.port) }),
      path: `${url.pathname || "/"}${url.search}`,
      method,
      headers: targetHeaders,
      agent,
    }, callback),
  };
}

class HttpConnectFallbackAgent extends HttpsAgent {
  constructor(private readonly proxy: URL, private readonly proxyAuthorization?: string) {
    super({ keepAlive: false });
  }

  override createConnection(options: { host?: string; hostname?: string; port?: number | string }, callback: (error: Error | null, socket?: Duplex) => void): Duplex | undefined {
    const targetHost = options.hostname ?? options.host ?? "";
    const targetPort = Number(options.port ?? 443);
    const connectRequest = (this.proxy.protocol === "https:" ? httpsRequest : httpRequest)({
      protocol: this.proxy.protocol,
      hostname: this.proxy.hostname,
      ...(this.proxy.port.length === 0 ? {} : { port: Number(this.proxy.port) }),
      method: "CONNECT",
      path: `${targetHost}:${targetPort}`,
      headers: {
        host: `${targetHost}:${targetPort}`,
        ...(this.proxyAuthorization === undefined ? {} : { "proxy-authorization": this.proxyAuthorization }),
      },
    });
    const fail = (error: Error): void => callback(error);
    connectRequest.once("error", fail);
    connectRequest.once("connect", (response, socket) => {
      if (response.statusCode !== 200) {
        socket.destroy();
        fail(new Error(`HTTP proxy CONNECT failed with status ${response.statusCode ?? 0}`));
        return;
      }
      const secureSocket = tlsConnect({ socket, servername: targetHost });
      secureSocket.once("error", fail);
      secureSocket.once("secureConnect", () => callback(null, secureSocket));
    });
    connectRequest.end();
    return undefined;
  }
}

class Socks5FallbackAgent extends HttpsAgent {
  constructor(private readonly proxy: URL) {
    super({ keepAlive: false });
  }

  override createConnection(options: { host?: string; hostname?: string; port?: number | string }, callback: (error: Error | null, socket?: Duplex) => void): Duplex | undefined {
    return createSocks5Connection(this.proxy, options, callback, true);
  }
}

class Socks5HttpFallbackAgent extends HttpAgent {
  constructor(private readonly proxy: URL) {
    super({ keepAlive: false });
  }

  override createConnection(options: { host?: string; hostname?: string; port?: number | string }, callback: (error: Error | null, socket?: Duplex) => void): Duplex | undefined {
    return createSocks5Connection(this.proxy, options, callback, false);
  }
}

function createSocks5Connection(
  proxy: URL,
  options: { host?: string; hostname?: string; port?: number | string },
  callback: (error: Error | null, socket?: Duplex) => void,
  secure: boolean,
): Duplex | undefined {
    const targetHost = options.hostname ?? options.host ?? "";
    const targetPort = Number(options.port ?? 80);
    const socket = netConnect({ host: proxy.hostname, port: Number(proxy.port || 1080) });
    const fail = (error: Error): void => {
      socket.destroy();
      callback(error);
    };
    socket.once("error", fail);
    socket.once("connect", () => {
      socket.write(Buffer.from([5, 1, 0]));
      let buffer = Buffer.alloc(0);
      const onGreeting = (chunk: Buffer): void => {
        buffer = Buffer.concat([buffer, chunk]);
        if (buffer.length < 2) return;
        if (buffer[0] !== 5 || buffer[1] !== 0) {
          fail(new Error("SOCKS5 proxy requires unauthenticated access"));
          return;
        }
        socket.off("data", onGreeting);
        const host = Buffer.from(targetHost);
        socket.write(Buffer.concat([
          Buffer.from([5, 1, 0, 3, host.length]),
          host,
          Buffer.from([(targetPort >> 8) & 0xff, targetPort & 0xff]),
        ]));
        buffer = Buffer.alloc(0);
        socket.on("data", onConnect);
      };
      const onConnect = (chunk: Buffer): void => {
        buffer = Buffer.concat([buffer, chunk]);
        if (buffer.length < 5) return;
        const addressType = buffer[3] ?? 0;
        const addressLength = addressType === 1 ? 4 : addressType === 4 ? 16 : 1 + (buffer[4] ?? 0);
        const packetLength = 4 + addressLength + 2;
        if (buffer.length < packetLength) return;
        socket.off("data", onConnect);
        if (buffer[0] !== 5 || buffer[1] !== 0) {
          fail(new Error(`SOCKS5 proxy CONNECT failed with status ${buffer[1] ?? 0}`));
          return;
        }
        if (!secure) {
          callback(null, socket);
          return;
        }
        const secureSocket = tlsConnect({ socket, servername: targetHost });
        secureSocket.once("error", fail);
        secureSocket.once("secureConnect", () => callback(null, secureSocket));
      };
      socket.on("data", onGreeting);
    });
    return undefined;
}


function fallbackRequestBody(body: unknown): Uint8Array | undefined {
  if (body === undefined || body === null) return undefined;
  if (typeof body === "string") return Buffer.from(body);
  if (body instanceof Uint8Array) return body;
  if (body instanceof ArrayBuffer) return new Uint8Array(body);
  if (ArrayBuffer.isView(body)) return new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
  if (body instanceof URLSearchParams) return Buffer.from(body.toString());
  throw new TypeError("The no-WebAssembly HTTP fallback only supports byte and text request bodies.");
}

function withDefaultUserAgent(init: RequestInit): RequestInit {
  const headers = new Headers(init.headers);
  if (!headers.has("user-agent")) headers.set("user-agent", defaultPluginUserAgent);
  return { ...init, headers };
}
