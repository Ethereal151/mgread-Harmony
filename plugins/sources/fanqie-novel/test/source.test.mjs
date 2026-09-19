import assert from 'node:assert/strict';
import test from 'node:test';
import * as plugin from '../dist/index.mjs';

test('Fanqie source keeps book/item IDs and formats paragraphs', async () => {
  const proxied = [];
  await plugin.activate({
    log: { info() {}, warn() {} },
    resource: { proxy(value) { proxied.push(value); return 'http://127.0.0.1/r'; } },
    http: { async fetch(input) {
      const url = String(input);
      if (url.includes('book_list')) return Response.json({ code: 0, data: { data: [{ book_id: '12', book_name: '测试书', author: '作者', thumb_url: 'https://img.example/a~tplv.heic' }] } });
      if (url.includes('/info?')) return Response.json({ data: { data: { book_name: '测试书', author: '作者', thumb_url: 'https://img.example/a.jpg' } } });
      if (url.includes('/directory/')) return Response.json({ data: { chapterListWithVolume: [[{ itemId: '34', title: '第一章' }]] } });
      if (url.includes('/content?')) return Response.json({ code: 0, data: { content: '<article><p>第一段</p><p>第二段</p></article>' } });
      throw new Error(url);
    } },
  });
  const home = await plugin.discover({ target: null, cursor: null, collectionId: null, pageSize: 3 });
  const result = await plugin.discover({ target: 'channel:1', cursor: null, collectionId: null, pageSize: 3 });
  const item = result.document.components[0].children[0].items[0].content;
  const chapters = await plugin.getChapters({ id: item.id });
  const content = await plugin.getContent({ id: item.id, chapterId: chapters.items[0].id });
  assert.equal(item.id, 'novel:12');
  assert.equal(home.document.components[0].icon, 'book');
  assert.equal(home.document.components[0].children[0].categories[0].icon, 'book');
  assert.equal(chapters.items[0].id, 'novel:12:34');
  assert.equal(content.text, '第一段\n\n第二段');
  assert.match(proxied[0].url, /p6-novel\.byteimg\.com/u);
});

test('Fanqie source migrates legacy search payloads and web detail fallback', async () => {
  const resources = [];
  await plugin.activate({
    log: { info() {}, warn() {} },
    resource: { proxy(value) { resources.push(value); return 'http://127.0.0.1/resource'; } },
    http: { async fetch(input) {
      const url = String(input);
      if (url.includes('fq-book.netsite.cc/search?')) return Response.json({ data: { has_more: false, search_tabs: [{ data: [{ book_data: { 0: { book_id: '55', book_name: '<em>旧版书</em>', author: '<em>旧作者</em>', thumb_url: 'https://img.example/cover~tplv.jpg' } } }] }] } });
      if (url.includes('fq-book.netsite.cc/info?')) return Response.json({ data: { data: {} } });
      if (url.includes('fanqienovel.com/page/66')) return new Response('<html><head><title>网页书_番茄小说</title><meta name="description" content="网页简介"></head><body><script type="application/ld+json">{"headline":"网页书","author":{"name":"网页作者"},"image":"https://img.example/web.jpg"}</script></body></html>');
      throw new Error(url);
    } },
  });
  const result = await plugin.search({ query: '旧版书', cursor: null, pageSize: 5 });
  const detail = await plugin.getDetail({ id: 'novel:66' });
  assert.equal(result.items[0].id, 'novel:55');
  assert.equal(result.items[0].title, '旧版书');
  assert.equal(detail.title, '网页书');
  assert.equal(detail.author, '网页作者');
  assert.equal(detail.description, '网页简介');
  assert.equal(resources.length, 2);
});

test('Fanqie source strips legacy inline image blocks from novel text', async () => {
  await plugin.activate({
    log: { info() {} },
    resource: { proxy() { return 'http://127.0.0.1/resource'; } },
    http: { async fetch(input) {
      if (String(input).includes('/content?')) return Response.json({ data: { content: '<article><p idx="0">第一段<img src="https://img.example/in-body.jpg"></p><div data-fanqie-type="image"><img src="https://img.example/only-image.jpg"></div><p idx="1">第二段</p></article>' } });
      throw new Error(String(input));
    } },
  });
  const content = await plugin.getContent({ id: 'novel:12', chapterId: 'novel:12:34' });
  assert.equal(content.text, '第一段\n\n第二段');
  assert.doesNotMatch(content.text, /img\.example/u);
});
