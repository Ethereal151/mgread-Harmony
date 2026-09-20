import assert from 'node:assert/strict';
import test from 'node:test';
import * as plugin from '../dist/index.mjs';

test('live Xiaowei discovery, search and playable detail remain reachable', { timeout: 60_000 }, async () => {
  await plugin.activate({ log: { info() {}, warn() {} }, resource: { proxy() { return 'http://127.0.0.1/live-resource'; } }, http: { fetch: (input, init = {}) => fetch(input, { ...init, signal: AbortSignal.timeout(15_000) }) } });
  const root = await plugin.discover({ target: null, cursor: null, collectionId: null, pageSize: 5 });
  const target = root.document.components[0].children[0].categories[0]?.target; assert.ok(target);
  const result = await plugin.discover({ target, cursor: null, collectionId: null, pageSize: 3 });
  const candidate = result.document.components[0].children[0].items[0]?.content; assert.ok(candidate);
  const search = await plugin.search({ query: candidate.title, cursor: null, pageSize: 8 });
  assert.ok(search.items.some((item) => item.id === candidate.id));
  const chapters = await plugin.getChapters({ id: candidate.id }); assert.ok(chapters.items.length > 0);
  const content = await plugin.getContent({ id: candidate.id, chapterId: chapters.items[0].id });
  assert.match(content.media.url, /^http:\/\/127\.0\.0\.1\//u);
});
