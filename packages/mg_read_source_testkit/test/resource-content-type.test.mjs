import assert from 'node:assert/strict';
import test from 'node:test';

import { probeReachableResource } from '../index.js';

test('image MIME sniffing reuses one response and keeps signature validation strict', async () => {
  const url = 'https://images.example/cover.png';
  let fetches = 0;
  let tailPulls = 0;
  const first = Uint8Array.from([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50]);
  const result = await probeReachableResource({
    requests: [{
      kind: 'image',
      url,
      headers: {},
      resourceTransform: 'sniff-image-content-type-v1',
    }],
    async fetch() {
      fetches += 1;
      return new Response(new ReadableStream({
        start(controller) { controller.enqueue(first); },
        pull(controller) {
          tailPulls += 1;
          controller.enqueue(Uint8Array.from([1, 2, 3]));
          controller.close();
        },
      }, { highWaterMark: 0 }), { headers: { 'content-type': 'image/png' } });
    },
    expectedKind: 'image',
    expectedContentType: /^image\/webp$/u,
    validatePrefix(bytes, contentType) {
      return contentType === 'image/webp'
        && Buffer.from(bytes.subarray(0, 4)).toString('ascii') === 'RIFF'
        && Buffer.from(bytes.subarray(8, 12)).toString('ascii') === 'WEBP';
    },
  });

  assert.equal(fetches, 1);
  assert.equal(tailPulls, 0);
  assert.equal(result.contentType, 'image/webp');
  assert.equal(result.bytesRead, first.byteLength);
});
