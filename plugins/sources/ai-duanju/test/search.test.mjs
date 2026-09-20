import assert from 'node:assert/strict';
import test from 'node:test';
import * as plugin from '../dist/index.mjs';

const title = 'AI真人版短剧 测试主题 很长的补充描述';
const listing = `<article><meta itemprop="url mainEntityOfPage" content="/archives/12/"><meta itemprop="name" content="作者"><meta itemprop="dateModified" content="2026-09-04"><div class="post-card-title">${title}</div><div class="post-card-info">AI剧场</div></article>`;

test('search retries a bounded title prefix and recovers the same stable ID', async () => {
  const searchPaths = [];
  await plugin.activate({
    log: { info() {} },
    resource: { proxy() { return 'http://127.0.0.1/r'; } },
    http: {
      async fetch(input) {
        const url = new URL(input);
        if (url.pathname.startsWith('/search/')) {
          const decoded = decodeURIComponent(url.pathname);
          searchPaths.push(decoded);
          return new Response(decoded.includes('很长的补充描述') ? '<main></main>' : listing);
        }
        return new Response(new Uint8Array());
      },
    },
  });

  const result = await plugin.search({ query: title, cursor: null, pageSize: 1 });
  assert.equal(result.items[0].id, 'video:12');
  assert.deepEqual(searchPaths, [
    `/search/${title}/`,
    '/search/AI真人版短剧 测试主题/',
  ]);
});
