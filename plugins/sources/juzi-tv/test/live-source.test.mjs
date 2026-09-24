import assert from 'node:assert/strict';
import test from 'node:test';

import * as plugin from '../dist/index.mjs';

test('live Juzi TV home, catalog and HLS media remain reachable', { timeout: 90_000 }, async () => {
  let resourceId = 0;
  let mediaRequest;
  await plugin.activate({
    log: { info() {}, warn() {} },
    resource: {
      proxy(request) {
        resourceId += 1;
        if (request.kind === 'hls' || request.kind === 'video') mediaRequest = request;
        return `http://127.0.0.1:9000/v1/source-resource/${String(resourceId).padStart(16, '0')}`;
      },
    },
    http: {
      fetch: (input, init = {}) =>
        fetch(input, { ...init, signal: AbortSignal.timeout(20_000) }),
    },
  });

  const home = await plugin.discover({
    target: null,
    cursor: null,
    collectionId: null,
    pageSize: 3,
  });
  assert.deepEqual(
    home.document.components.map((component) => component.id),
    [
      'juzi-home-short-section',
      'juzi-home-navigation',
      'juzi-home-movie-section',
      'juzi-home-series-section',
    ],
  );
  assert.ok(Buffer.byteLength(JSON.stringify(home), 'utf8') < 56 * 1024);

  const catalog = await plugin.discover({
    target: 'channel:short',
    cursor: null,
    collectionId: null,
    pageSize: 1,
  });
  const selected = catalog.document.components[0].children[0].items[0].content;
  assert.ok(selected.coverUrl !== null);

  const detail = await plugin.getDetail({ id: selected.id });
  const chapters = await plugin.getChapters({ id: detail.id });
  assert.ok(chapters.items.length > 0);
  const content = await plugin.getContent({
    id: detail.id,
    chapterId: chapters.items[0].id,
  });
  assert.equal(content.contentKind, 'video');
  assert.equal(content.media.resourceType, 'hls');
  assert.equal(mediaRequest.kind, 'hls');

  const root = await fetch(mediaRequest.url, {
    headers: mediaRequest.headers,
    redirect: 'follow',
    signal: AbortSignal.timeout(20_000),
  });
  const rootPrefix = await readPrefix(root);
  assert.ok(root.ok, `HLS root status ${root.status}`);
  assert.match(rootPrefix.text, /^#EXTM3U/u);

  let playlistUrl = root.url;
  let playlistText = rootPrefix.text;
  for (let depth = 0; depth < 2 && /#EXT-X-STREAM-INF/u.test(playlistText); depth += 1) {
    const child = firstPlaylistUri(playlistText);
    assert.ok(child);
    const response = await fetch(new URL(child, playlistUrl), {
      headers: mediaRequest.headers,
      redirect: 'follow',
      signal: AbortSignal.timeout(20_000),
    });
    const prefix = await readPrefix(response);
    assert.ok(response.ok, `HLS child status ${response.status}`);
    assert.match(prefix.text, /^#EXTM3U/u);
    playlistUrl = response.url;
    playlistText = prefix.text;
  }

  const segment = firstMediaUri(playlistText);
  assert.ok(segment);
  const segmentResponse = await fetch(new URL(segment, playlistUrl), {
    headers: { ...mediaRequest.headers, Range: 'bytes=0-65535' },
    redirect: 'follow',
    signal: AbortSignal.timeout(20_000),
  });
  const segmentPrefix = await readPrefix(segmentResponse);
  assert.ok(segmentResponse.ok, `HLS segment status ${segmentResponse.status}`);
  assert.ok(segmentPrefix.bytes > 0);
});

test('live Juzi TV fixed content IDs load detail, cover, catalog and media', { timeout: 180_000 }, async () => {
  const proxied = [];
  await plugin.activate({
    log: { info() {}, warn() {} },
    resource: {
      proxy(request) {
        proxied.push(request);
        return `http://127.0.0.1:9000/v1/source-resource/${String(proxied.length).padStart(16, '0')}`;
      },
    },
    http: {
      fetch: (input, init = {}) => fetch(input, { ...init, signal: AbortSignal.timeout(20_000) }),
    },
  });

  for (const id of ['vod:458764', 'vod:35736']) {
    const detail = await plugin.getDetail({ id });
    assert.equal(detail.id, id);
    assert.ok(detail.coverUrl);
    const cover = proxied.find((request) => request.kind === 'image' && request.url);
    assert.ok(cover, `${id} cover proxy was not registered`);
    const coverResponse = await fetch(cover.url, {
      headers: cover.headers,
      redirect: 'follow',
      signal: AbortSignal.timeout(20_000),
    });
    assert.ok(coverResponse.ok, `${id} cover status ${coverResponse.status}`);
    await coverResponse.body?.cancel();

    const chapters = await plugin.getChapters({ id });
    assert.ok(chapters.items.length > 0, `${id} has no chapters`);
    for (const group of chapters.groups) {
      assert.deepEqual(group.episodes.map((episode) => episode.order), group.episodes.map((_, index) => index));
      assert.ok(group.episodes.length <= 2000, `${id} has a line over 2000 episodes`);
    }

    const candidates = chapters.groups.length > 0
      ? chapters.groups.map((group) => group.episodes[0]).filter(Boolean)
      : [chapters.items[0]];
    let playable = false;
    for (const chapter of candidates) {
      assert.ok(chapter);
      const content = await plugin.getContent({ id, chapterId: chapter.id });
      assert.equal(content.chapterId, chapter.id);
      assert.equal(content.contentKind, 'video');
      assert.ok(content.media);
      const media = proxied.at(-1);
      assert.ok(media && (media.kind === 'hls' || media.kind === 'video'));
      const mediaResponse = await fetch(media.url, {
        headers: media.headers,
        redirect: 'follow',
        signal: AbortSignal.timeout(20_000),
      });
      const prefix = await readPrefix(mediaResponse);
      if (!mediaResponse.ok) {
        console.warn(`${id} line ${chapter.id} returned ${mediaResponse.status}; trying another published line`);
        continue;
      }
      if (media.kind === 'hls') assert.match(prefix.text, /^#EXTM3U/u);
      else assert.ok(prefix.bytes > 0, `${id} media returned no bytes`);
      playable = true;
      break;
    }
    assert.equal(playable, true, `${id} has no currently reachable published line`);
  }
});

function firstPlaylistUri(text) {
  const lines = text.split(/\r?\n/u).map((line) => line.trim());
  const marker = lines.findIndex((line) => line.startsWith('#EXT-X-STREAM-INF'));
  return lines.slice(marker + 1).find((line) => line !== '' && !line.startsWith('#')) ?? null;
}

function firstMediaUri(text) {
  return text.split(/\r?\n/u)
    .map((line) => line.trim())
    .find((line) => line !== '' && !line.startsWith('#') && !/\.m3u8(?:$|[?#])/iu.test(line)) ?? null;
}

async function readPrefix(response) {
  const reader = response.body?.getReader();
  if (reader === undefined) return { bytes: 0, text: '' };
  const chunks = [];
  let bytes = 0;
  try {
    while (bytes < 64 * 1024) {
      const next = await reader.read();
      if (next.done || next.value === undefined) break;
      const remaining = 64 * 1024 - bytes;
      const chunk = next.value.slice(0, remaining);
      chunks.push(Buffer.from(chunk));
      bytes += chunk.byteLength;
      if (chunk.byteLength < next.value.byteLength) break;
    }
  } finally {
    await reader.cancel().catch(() => {});
  }
  return { bytes, text: Buffer.concat(chunks).toString('utf8') };
}
