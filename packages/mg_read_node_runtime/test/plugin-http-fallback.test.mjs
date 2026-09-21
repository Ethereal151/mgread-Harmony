import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";
import { gzipSync } from "node:zlib";

import { ConfigurablePluginHttpClient } from "../dist/plugin-http-client.js";

test("native HTTP fallback serves direct requests when WebAssembly is unavailable", async (t) => {
  const server = http.createServer((request, response) => {
    if (request.url === "/redirect") {
      response.writeHead(302, { location: "/content" });
      response.end();
      return;
    }
    if (request.url === "/gzip") {
      const body = gzipSync("gzip-fallback:ok");
      response.writeHead(200, { "content-encoding": "gzip", "content-length": body.byteLength });
      response.end(body);
      return;
    }
    response.writeHead(200, { "content-type": "text/plain" });
    response.end(`fallback:${request.headers["user-agent"]}`);
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  t.after(() => new Promise((resolve, reject) => server.close((error) => error === undefined ? resolve() : reject(error))));

  const address = server.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const client = new ConfigurablePluginHttpClient();
  t.after(() => client.close());

  const response = await client.fetch(`http://127.0.0.1:${address.port}/redirect`, {});
  assert.equal(response.status, 200);
  assert.match(await response.text(), /^fallback:/);

  const gzipResponse = await client.fetch(`http://127.0.0.1:${address.port}/gzip`, {});
  assert.equal(gzipResponse.status, 200);
  assert.equal(await gzipResponse.text(), "gzip-fallback:ok");
});
