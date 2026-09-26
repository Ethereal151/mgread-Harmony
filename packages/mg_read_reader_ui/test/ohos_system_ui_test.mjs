/** Execute the real ETS window owner against asynchronous platform doubles.
 * Node 24+: node --test test/ohos_system_ui_test.mjs
 * This validates ordering/state, not ArkTS compilation or device rendering.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL(
  '../ohos/src/main/ets/com/example/novel_reader_ui/NovelReaderUiPlugin.ets',
  import.meta.url,
), 'utf8').replace(/^import[\s\S]*?from '[^']+'\r?\n/gm, '')
  .replace('export default class', 'class');
const loadPlugin = new Function('window', 'inputConsumer', 'KeyCode',
  stripTypeScriptTypes(source) + '\nreturn NovelReaderUiPlugin;');

function fixture() {
  const state = { layout: false, bars: [], properties: {}, keep: false };
  const calls = [];
  let inFlight = 0;
  let maxInFlight = 0;
  let failNext = false;
  const perform = async (name, value, apply) => {
    calls.push([name, value]);
    maxInFlight = Math.max(maxInFlight, ++inFlight);
    await new Promise(resolve => setImmediate(resolve));
    --inFlight;
    if (failNext) { failNext = false; throw new Error('window unavailable'); }
    apply();
  };
  const target = {
    setWindowLayoutFullScreen: v => perform('layout', v, () => { state.layout = v; }),
    setWindowSystemBarEnable: v => perform('bars', v, () => { state.bars = v; }),
    setWindowSystemBarProperties: v => perform('properties', v,
      () => { Object.assign(state.properties, v); }),
    setWindowKeepScreenOn: v => perform('keep', v, () => { state.keep = v; }),
    setPreferredOrientation: v => perform('orientation', v,
      () => { state.orientation = v; }),
  };
  const Plugin = loadPlugin({
    getLastWindow: async () => target,
    Orientation: { LANDSCAPE: 'landscape', PORTRAIT: 'portrait' },
  }, {}, {});
  const plugin = new Plugin();
  plugin.onAttachedToAbility({ getAbility: () => ({ context: {} }) });
  const invoke = (method, args = {}) => new Promise((resolve, reject) => {
    plugin.onMethodCall({ method, args: new Map(Object.entries(args)) }, {
      success: resolve,
      error: (code, message) => reject(new Error(`${code}: ${message}`)),
      notImplemented: () => reject(new Error('not implemented')),
    });
  });
  return { plugin, invoke, state, calls, maxInFlight: () => maxInFlight,
    failNext: () => { failNext = true; } };
}
const pageStyle = {
  statusBarColor: '#FFFAF0E0', navigationBarColor: '#FFFAF0E0',
  statusBarContentColor: '#FF202020', navigationBarContentColor: '#FF202020',
};

test('normal, reader and restored pages keep one edge-to-edge layout contract', async () => {
  const f = fixture();
  await f.invoke('setApplicationSystemUiStyle', pageStyle);
  assert.equal(f.state.layout, true);
  assert.deepEqual(f.state.bars, ['status', 'navigation']);
  await f.invoke('setReaderSystemUi', { keepScreenOn: true, immersiveMode: true });
  assert.deepEqual(f.state.bars, []);
  await f.invoke('setApplicationSystemUiStyle', { ...pageStyle, statusBarColor: '#FF111111' });
  assert.deepEqual(f.state.bars, [], 'background theme must not reveal reader bars');
  await f.invoke('setReaderSystemUi', { keepScreenOn: false, immersiveMode: false });
  assert.equal(f.state.properties.statusBarColor, '#00000000');
  assert.deepEqual(f.state.bars, ['status', 'navigation']);
  await f.invoke('restoreApplicationSystemUi');
  assert.equal(f.state.properties.statusBarColor, '#FF111111');
  assert.equal(f.state.keep, false);
  assert.ok(f.calls.filter(([name]) => name === 'layout').every(([, v]) => v === true));
});

test('portrait audio/video preserves visible transparent bars during keep-awake requests', async () => {
  const f = fixture();
  await f.invoke('setVideoWindowMode', { fullscreen: false });
  await f.invoke('setReaderSystemUi', { keepScreenOn: true, immersiveMode: false });
  await f.invoke('setApplicationSystemUiStyle', pageStyle);
  assert.equal(f.state.layout, true);
  assert.deepEqual(f.state.bars, ['status', 'navigation']);
  assert.equal(f.state.properties.statusBarColor, '#00000000');
  assert.equal(f.state.properties.statusBarContentColor, '#FFFFFF');
  await f.invoke('setVideoWindowMode', { fullscreen: true });
  assert.deepEqual(f.state.bars, []);
  await f.invoke('restoreApplicationSystemUi');
  assert.deepEqual(f.state.bars, ['status', 'navigation']);
  assert.equal(f.state.layout, true);
  assert.equal(f.state.properties.statusBarColor, pageStyle.statusBarColor);
});

test('overlapping restore, media and page requests execute in order', async () => {
  const f = fixture();
  await Promise.all([
    f.invoke('setApplicationSystemUiStyle', pageStyle),
    f.invoke('setVideoWindowMode', { fullscreen: false }),
    f.invoke('restoreApplicationSystemUi'),
    f.invoke('setVideoWindowMode', { fullscreen: true }),
    f.invoke('setApplicationSystemUiStyle', pageStyle),
  ]);
  assert.equal(f.maxInFlight(), 1);
  assert.equal(f.state.layout, true);
  assert.equal(f.state.orientation, 'landscape');
  assert.deepEqual(f.state.bars, []);
});

test('failed window request does not block the next mode', async () => {
  const f = fixture();
  f.failNext();
  await assert.rejects(f.invoke('setApplicationSystemUiStyle', pageStyle), /operation_failed/);
  await f.invoke('setVideoWindowMode', { fullscreen: false });
  assert.equal(f.state.layout, true);
  assert.deepEqual(f.state.bars, ['status', 'navigation']);
});

test('engine detach finishes restoring bars after clearing the cached window', async () => {
  const f = fixture();
  await f.invoke('setVideoWindowMode', { fullscreen: true });
  f.plugin.onDetachedFromEngine({});
  for (let i = 0; i < 10; ++i) await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(f.state.bars, ['status', 'navigation']);
  assert.equal(f.state.layout, true);
  assert.equal(f.state.keep, false);
});
