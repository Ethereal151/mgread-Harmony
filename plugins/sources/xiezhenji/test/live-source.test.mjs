import assert from 'node:assert/strict';
import test from 'node:test';

test('live direct HTTP probe records the Cloudflare gate without claiming browser verification', { timeout: 30_000 }, async () => {
  const response = await fetch('https://xx.knit.bid/', { signal: AbortSignal.timeout(20_000) });
  const body = await response.text();
  assert.ok(response.status === 403 || /(?:cf-challenge|cf-turnstile|Just a moment|Checking your browser)/iu.test(body));
});
