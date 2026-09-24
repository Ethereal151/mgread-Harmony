/**
 * Characterizes the private control-dispatch ports extracted from DesktopRuntime.
 * These tests keep parameter parsing and wire-error projection stable without
 * duplicating the WebSocket and embedded transport integration coverage.
 */
import assert from "node:assert/strict";
import test from "node:test";

import { dispatchPluginStorageControl } from "../dist/desktop-plugin-cache-dispatch.js";
import {
  dispatchSourceContent,
  dispatchSourceResourceDecode,
} from "../dist/desktop-source-control-dispatch.js";
import { encodeSourceResourceToken } from "../dist/source-resource-token.js";

const pluginId = "org.example.source";

function makeRequest(params, deadlineUnixMs = Date.now() + 60_000) {
  return {
    deadlineUnixMs,
    id: "request-1",
    method: "internal.test",
    params,
    traceId: "trace-1",
  };
}

function requestError(request, code, message) {
  return {
    code,
    message,
    requestId: request.id,
    traceId: request.traceId,
  };
}

test("plugin storage control keeps path-free operation routing and validation", async () => {
  const calls = [];
  const manager = {
    async listCacheUsage(selectedPluginId) {
      calls.push(["cacheUsage", selectedPluginId]);
      return [{ pluginId, bytes: 7 }];
    },
    async measureInstallationUsage(selectedPluginId, scope) {
      calls.push(["installationUsage", selectedPluginId, scope]);
      return { pluginId: selectedPluginId, scope, bytes: 11, fileCount: 2 };
    },
    async clearPluginCache(selectedPluginId) {
      calls.push(["cacheClear", selectedPluginId]);
      return { items: [] };
    },
    async clearAllPluginCaches() {
      calls.push(["cacheClearAll"]);
      return { items: [] };
    },
  };

  assert.deepEqual(
    await dispatchPluginStorageControl(
      makeRequest({}),
      manager,
      requestError,
      "cacheUsage",
    ),
    { result: [{ pluginId, bytes: 7 }] },
  );
  assert.deepEqual(
    await dispatchPluginStorageControl(
      makeRequest({ pluginId, scope: "data" }),
      manager,
      requestError,
      "installationUsage",
    ),
    { result: { pluginId, scope: "data", bytes: 11, fileCount: 2 } },
  );
  assert.deepEqual(
    await dispatchPluginStorageControl(
      makeRequest({ pluginId }),
      manager,
      requestError,
      "cacheClear",
    ),
    { result: { items: [] } },
  );
  assert.deepEqual(
    await dispatchPluginStorageControl(
      makeRequest({}),
      manager,
      requestError,
      "cacheClearAll",
    ),
    { result: { items: [] } },
  );
  assert.deepEqual(calls, [
    ["cacheUsage", undefined],
    ["installationUsage", pluginId, "data"],
    ["cacheClear", pluginId],
    ["cacheClearAll"],
  ]);

  const invalid = await dispatchPluginStorageControl(
    makeRequest({ scope: "cache" }),
    manager,
    requestError,
    "installationUsage",
  );
  assert.equal(invalid.error.code, "invalid_request");
  assert.equal(invalid.error.message, "The installed source size request is invalid.");
});

test("source content dispatch preserves every operation mapping", async () => {
  const calls = [];
  const manager = Object.fromEntries(
    ["discover", "search", "searchSuggestions", "getDetail", "getChapters", "getContent"].map(
      (name) => [name, async (...args) => {
        calls.push([name, ...args]);
        return { operation: name };
      }],
    ),
  );
  const cancellation = new AbortController().signal;
  const deadline = Date.now() + 60_000;
  const cases = [
    ["discover", { pluginId, target: null, cursor: null, collectionId: null, pageSize: 20 }],
    ["search", { pluginId, query: "query", cursor: null, pageSize: 20 }],
    ["searchSuggestions", { pluginId, cursor: null, pageSize: 20 }],
    ["getDetail", { pluginId, id: "book-1" }],
    ["getChapters", { pluginId, id: "book-1" }],
    ["getContent", { pluginId, id: "book-1", chapterId: "chapter-1" }],
  ];

  for (const [operation, params] of cases) {
    const dispatched = await dispatchSourceContent(
      makeRequest(params, deadline),
      manager,
      requestError,
      cancellation,
      operation,
    );
    assert.deepEqual(dispatched, { result: { operation } });
  }
  assert.deepEqual(
    calls.map(([name, selectedPluginId, request, signal, selectedDeadline]) => ({
      name,
      selectedPluginId,
      request,
      sameSignal: signal === cancellation,
      selectedDeadline,
    })),
    [
      { name: "discover", selectedPluginId: pluginId, request: { target: null, cursor: null, collectionId: null, pageSize: 20 }, sameSignal: true, selectedDeadline: deadline },
      { name: "search", selectedPluginId: pluginId, request: { query: "query", cursor: null, pageSize: 20 }, sameSignal: true, selectedDeadline: deadline },
      { name: "searchSuggestions", selectedPluginId: pluginId, request: { cursor: null, pageSize: 20 }, sameSignal: true, selectedDeadline: deadline },
      { name: "getDetail", selectedPluginId: pluginId, request: { id: "book-1" }, sameSignal: true, selectedDeadline: deadline },
      { name: "getChapters", selectedPluginId: pluginId, request: { id: "book-1" }, sameSignal: true, selectedDeadline: deadline },
      { name: "getContent", selectedPluginId: pluginId, request: { id: "book-1", chapterId: "chapter-1" }, sameSignal: true, selectedDeadline: deadline },
    ],
  );

  const invalid = await dispatchSourceContent(
    makeRequest({ pluginId }),
    manager,
    requestError,
    cancellation,
    "search",
  );
  assert.equal(invalid.error.code, "invalid_request");
  assert.equal(invalid.error.message, "The source capability request is invalid.");
});

test("source-resource decode stays bounded and returns only the descriptor", () => {
  const request = { kind: "audio", url: "https://media.example/audio.mp3", headers: {} };
  const token = encodeSourceResourceToken(pluginId, request);
  const decoded = dispatchSourceResourceDecode(
    makeRequest({ url: `http://127.0.0.1:39227/v1/source-resource/${token}` }),
    requestError,
  );
  assert.deepEqual(decoded, { result: { pluginId, request } });

  const invalid = dispatchSourceResourceDecode(
    makeRequest({ url: "https://example.test/not-a-resource" }),
    requestError,
  );
  assert.equal(invalid.error.code, "invalid_request");
  assert.equal(invalid.error.message, "The URL is not a valid Runtime source-resource URL.");
});
