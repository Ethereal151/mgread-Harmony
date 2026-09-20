import assert from'node:assert/strict';import test from'node:test';import*as plugin from'../dist/index.mjs';test('Qimao source maps stable episodes and proxies media',async()=>{const proxied=[];await plugin.activate({log:{info(){},warn(){}},resource:{proxy(v){proxied.push(v);return`http://127.0.0.1/r/${proxied.length}`;}},http:{async fetch(input){const url=String(input);if(url.includes('/detail?'))return Response.json({list:[{vod_id:'123',vod_name:'测试漫剧',vod_pic:'https://img.example/c.jpg',vod_play_url:'1$https://media.example/1.m3u8'}]});return Response.json({list:[{vod_id:'123',vod_name:'测试漫剧',vod_pic:'https://img.example/c.jpg'}]});}}});const listing=await plugin.discover({target:'channel:manju',cursor:null,collectionId:null,pageSize:5}),item=listing.document.components[0].children[0].items[0].content;assert.equal(item.id,'video:123');const chapters=await plugin.getChapters({id:item.id});assert.equal(chapters.items[0].id,'video:123:0');const content=await plugin.getContent({id:item.id,chapterId:chapters.items[0].id});assert.equal(content.media.resourceType,'video');assert.equal(proxied.at(-1).url,'https://media.example/1.m3u8');});

test('Qimao reports the upstream client-upgrade sentinel as access blocked', async () => {
  const raised = [];
  await plugin.activate({
    log: { info() {}, warn() {} },
    errors: { raise(error) { raised.push(error); throw Object.assign(new Error(error.message), { name: 'PluginManagerError', ...error }); } },
    resource: { proxy(value) { return value.url; } },
    http: { async fetch() { return Response.json({ list: [{ vod_id: 'upgrade_required', vod_name: '请更新到唐三最新版', vod_remarks: '找唐三' }] }); } },
  });

  await assert.rejects(
    () => plugin.discover({ target: 'channel:manju', cursor: null, collectionId: null, pageSize: 5 }),
    (error) => error.code === 'source_access_blocked',
  );
  assert.equal(raised[0].annotation, '请更新到唐三最新版');
});
