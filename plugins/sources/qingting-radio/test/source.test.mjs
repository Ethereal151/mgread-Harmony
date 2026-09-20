import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import test from 'node:test';
import * as plugin from '../dist/index.mjs';

test('Qingting GraphQL, detail and live audio are native and stable', async () => {
  const calls = [];
  const resources = [];
  await plugin.activate({
    log: { info() {}, warn() {} },
    resource: {
      proxy(value) {
        resources.push(value);
        return 'http://127.0.0.1/resource/opaque';
      },
    },
    http: {
      async fetch(input, init = {}) {
        const url = String(input);
        calls.push({ url, init });
        if (url.includes('/api/pc/radio/')) {
          return Response.json({ data: { id: 101, title: '测试电台', description: '详情' } });
        }
        const body = JSON.parse(init.body);
        if (body.query.includes('searchResultsPage')) {
          return Response.json({ data: { searchResultsPage: { searchData: [{ id: 101, title: '测试电台' }], numFound: 1 } } });
        }
        return Response.json({ data: { radioPage: { contents: [{ id: 101, title: '测试电台', imgUrl: '/cover.jpg' }] } } });
      },
    },
  });

  const root = await plugin.discover({ target: null, cursor: null, collectionId: null, pageSize: 5 });
  assert.ok(root.document.components[0].children[0].categories.length > 40);
  const list = await plugin.discover({ target: 'category:217', cursor: null, collectionId: null, pageSize: 5 });
  const id = list.document.components[0].children[0].items[0].content.id;
  assert.equal(id, 'radio:MTAx');
  const found = await plugin.search({ query: '测试', cursor: null, pageSize: 5 });
  assert.equal(found.totalCount, 1);
  const detail = await plugin.getDetail({ id });
  assert.equal(detail.description, '详情');
  assert.equal(detail.coverUrl, 'http://127.0.0.1/resource/opaque');
  const chapters = await plugin.getChapters({ id });
  const content = await plugin.getContent({ id, chapterId: chapters.items[0].id });
  assert.equal(content.media.resourceType, 'audio');
  assert.equal(content.media.resourcePolicy, 'refreshable');
  assert.ok(Date.parse(content.media.expiresAt) > Date.now());
  const audio = resources.find((resource) => resource.kind === 'audio');
  const audioUrl = new URL(audio.url);
  assert.equal(`${audioUrl.origin}${audioUrl.pathname}`, 'https://lhttp-hw.qtfm.cn/live/101/64k.mp3');
  assert.equal(audioUrl.searchParams.get('app_id'), 'web');
  const timestamp = audioUrl.searchParams.get('ts');
  const canonical = `app_id=web&path=${encodeURIComponent(audioUrl.pathname)}&ts=${timestamp}`;
  assert.equal(audioUrl.searchParams.get('sign'), createHmac('md5', 'Lwrpu$K5oP').update(canonical).digest('hex'));
  assert.equal(new Date(Number.parseInt(timestamp, 16) * 1000).toISOString(), content.media.expiresAt);
  assert.ok(calls.some((call) => call.url === 'https://webbff.qtfm.cn/www' && call.init.method === 'POST'));
});
