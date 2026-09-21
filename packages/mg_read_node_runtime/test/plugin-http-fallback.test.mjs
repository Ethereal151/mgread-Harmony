import assert from "node:assert/strict";
import http from "node:http";
import net from "node:net";
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

  const proxy = http.createServer((proxyRequest, proxyResponse) => {
    const target = new URL(proxyRequest.url);
    const upstream = http.request({
      hostname: target.hostname,
      port: Number(target.port),
      path: `${target.pathname}${target.search}`,
      method: proxyRequest.method,
      headers: proxyRequest.headers,
    }, (upstreamResponse) => {
      proxyResponse.writeHead(upstreamResponse.statusCode ?? 502, upstreamResponse.headers);
      upstreamResponse.pipe(proxyResponse);
    });
    upstream.once("error", (error) => {
      proxyResponse.writeHead(502);
      proxyResponse.end(String(error));
    });
    proxyRequest.pipe(upstream);
  });
  await new Promise((resolve, reject) => {
    proxy.once("error", reject);
    proxy.listen(0, "127.0.0.1", resolve);
  });
  t.after(() => new Promise((resolve, reject) => proxy.close((error) => error === undefined ? resolve() : reject(error))));
  const proxyAddress = proxy.address();
  assert.notEqual(proxyAddress, null);
  assert.notEqual(typeof proxyAddress, "string");
  client.configure(`http://127.0.0.1:${proxyAddress.port}/`);
  const proxied = await client.fetch(`http://127.0.0.1:${address.port}/content`, {});
  assert.equal(proxied.status, 200);
  assert.match(await proxied.text(), /^fallback:/);
  client.configure(undefined);

  const socks = createSocks5Proxy();
  await new Promise((resolve, reject) => {
    socks.once("error", reject);
    socks.listen(0, "127.0.0.1", resolve);
  });
  t.after(() => new Promise((resolve, reject) => socks.close((error) => error === undefined ? resolve() : reject(error))));
  const socksAddress = socks.address();
  assert.notEqual(socksAddress, null);
  assert.notEqual(typeof socksAddress, "string");
  client.configure(`socks5://127.0.0.1:${socksAddress.port}/`);
  const socksResponse = await client.fetch(`http://127.0.0.1:${address.port}/content`, {});
  assert.equal(socksResponse.status, 200);
  assert.match(await socksResponse.text(), /^fallback:/);
});

function createSocks5Proxy() {
  return net.createServer((downstream) => {
    let buffer = Buffer.alloc(0);
    let stage = "greeting";
    const read = (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      if (stage === "greeting") {
        if (buffer.length < 3) return;
        assert.deepEqual([...buffer.subarray(0, 3)], [5, 1, 0]);
        buffer = buffer.subarray(3);
        downstream.write(Buffer.from([5, 0]));
        stage = "connect";
      }
      if (stage !== "connect" || buffer.length < 7) return;
      const hostLength = buffer[4];
      const packetLength = 7 + hostLength;
      if (buffer.length < packetLength) return;
      const host = buffer.subarray(5, 5 + hostLength).toString();
      const port = buffer.readUInt16BE(5 + hostLength);
      buffer = buffer.subarray(packetLength);
      const upstream = net.connect(port, host, () => {
        downstream.write(Buffer.from([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]));
        if (buffer.length > 0) upstream.write(buffer);
        downstream.off("data", read);
        downstream.pipe(upstream);
        upstream.pipe(downstream);
      });
      upstream.once("error", () => downstream.destroy());
    };
    downstream.on("data", read);
  });
}
