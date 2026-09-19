import assert from "node:assert/strict";
import test from "node:test";

import * as fixture from "./ohos_stage2_browser_source/index.mjs";

function contextFor(pluginId, overrides = {}) {
  const calls = [];
  const page = {
    async navigate() { calls.push("navigate"); },
    async executeJavaScript(code) { calls.push(["js", code]); return code === "document.cookie" ? "mgread_stage2=verified" : "MgRead OHOS Stage 2"; },
    async getHtml() { calls.push("html"); return "Example Domain"; },
    async getUrl() { calls.push("url"); return "https://example.com/"; },
    async show() { calls.push("show"); },
    async hide() { calls.push("hide"); },
    async close() { calls.push("close"); },
  };
  let coordinateCalls = 0;
  return {
    calls,
    context: {
      app: { nodeVersion: "24.16.0", pluginApi: 1, runtimeVersion: "fixture" },
      cacheDir: ".cache",
      dataDir: ".data",
      errors: { raise() { throw new Error("unexpected public error"); } },
      http: { fetch: async () => new Response("ok") },
      browser: { sessionV1: {
        async request() { calls.push("browser.html"); return { version: 1, status: 200, finalUrl: "https://example.com/", headers: { "content-type": "text/html" }, body: "Example Domain" }; },
        async requestCoordinates(request) {
          calls.push(["coordinates", request.presentation]);
          coordinateCalls += 1;
          if (coordinateCalls === 1) throw { name: "PluginBrowserSessionError", code: "interaction_required" };
          return { version: 1, accepted: true, action: "coordinates", x: 0, y: 0, width: 10, height: 10 };
        },
        async nativeInput() { return { version: 1, accepted: true, action: "native-input" }; },
        async controlClick() { return { version: 1, accepted: true, action: "control-click" }; },
      } },
      webview: { open: async () => page },
      resource: { proxy: ({ url }) => `http://127.0.0.1/resource?url=${encodeURIComponent(url)}` },
      log: { debug() {}, error() {}, info() {}, warn() {} },
      plugin: { id: pluginId, version: "0.1.0" },
      ...overrides,
    },
  };
}

test("OHOS Stage 2 fixture exposes the complete source surface", async () => {
  const { context } = contextFor("org.mgread.ohos.stage2.source-one");
  await fixture.activate(context);
  const discovery = await fixture.discover({ target: null, cursor: null, collectionId: null, pageSize: 20 });
  const search = await fixture.search({ query: "stage2", cursor: null, pageSize: 20 });
  const detail = await fixture.getDetail({ id: search.items[0].content.id });
  const chapters = await fixture.getChapters({ id: detail.id });
  const content = await fixture.getContent({ id: detail.id, chapterId: chapters.items[0].id });
  assert.equal(discovery.kind, "document");
  assert.equal(search.items.length, 1);
  assert.match(detail.coverUrl, /^http:\/\/127\.0\.0\.1\//);
  assert.equal(chapters.items.length, 2);
  assert.match(content.text, /Runtime/);
});

test("OHOS Stage 2 fixture exercises browser.session.v1 Cookie/JS and interaction recovery", async () => {
  const cookie = contextFor("org.mgread.ohos.stage2.cookie-js");
  await fixture.activate(cookie.context);
  assert.match((await fixture.search({ query: "stage2" })).items[0].content.title, /^cookie-js:200:true:true$/);

  const interaction = contextFor("org.mgread.ohos.stage2.interaction");
  await fixture.activate(interaction.context);
  assert.equal((await fixture.search({ query: "stage2" })).items[0].content.title, "interaction_required:true");
  assert.deepEqual(interaction.calls.filter((value) => Array.isArray(value) && value[0] === "coordinates"), [
    ["coordinates", "hidden"],
    ["coordinates", "visible"],
  ]);
});
