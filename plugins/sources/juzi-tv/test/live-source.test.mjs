import assert from 'node:assert/strict';
import test from 'node:test';

import * as plugin from '../dist/index.mjs';

test('live Juzi TV home and catalog remain reachable', { timeout: 90_000 }, async () => {
  let resourceId = 0;
  await plugin.activate({
    log: { info() {}, warn() {} },
    resource: {
      proxy() {
        resourceId += 1;
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
  for (const section of home.document.components.filter(
    (component) => component.type === 'section',
  )) {
    const items = section.children[0].items;
    assert.ok(items.length > 0);
    assert.ok(items.every((item) => item.content.coverUrl !== null));
  }

  const catalog = await plugin.discover({
    target: 'channel:short',
    cursor: null,
    collectionId: null,
    pageSize: 3,
  });
  assert.ok(catalog.document.components[0].children[0].items.length > 0);
});
