#!/usr/bin/env node
// Test of the image builder page's script (site/assets/start.js, the page /start/).
//
//     python3 tool/site/build.py        # builds the page and the WebAssembly (tool/site/wasm.sh)
//     node tool/site/test_start.mjs
//
// It runs the page's own functions under Node with the built WebAssembly
// (site/dist/assets/wasm) against a fixture index and a small fake base image
// written as one gzip member:
//   - a download that does not match its entry (size, SHA-256) is refused and
//     never cached; a cached one is checked again;
//   - the assembly changes the region's bytes only, its output is one gzip
//     member whose ISIZE is the image size, and the download is left as it was;
//   - an image of another length is refused;
//   - the replace step hands on each chunk as it comes (it streams);
//   - the file name is plain;
//   - on the page (a DOM stub): the Download button waits for "I wrote it
//     down", and a site the device refuses shows the device's words and no code.
// Node 20+, no dependencies.

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import vm from 'node:vm';
import zlib from 'node:zlib';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SCRIPT = path.join(REPO, 'site/assets/start.js');
const WASM_DIR = path.join(REPO, 'site/dist/assets/wasm');

// ---------------------------------------------------------------- the code
const glue = path.join(WASM_DIR, 'wyrm_image_web.js');
if (!fs.existsSync(glue)) {
  console.error(`start: ${glue} is missing: run python3 tool/site/build.py (or tool/site/wasm.sh) first`);
  process.exit(1);
}
const wasm = await import(pathToFileURL(glue).href);
wasm.initSync({ module: fs.readFileSync(path.join(WASM_DIR, 'wyrm_image_web_bg.wasm')) });

vm.runInThisContext(fs.readFileSync(SCRIPT, 'utf8'), { filename: SCRIPT });
const S = globalThis.wyrmStart;
if (!S) {
  console.error('start: start.js did not export globalThis.wyrmStart');
  process.exit(1);
}
const CONFIG_SIZE = 4 * 1024 * 1024;
assert.equal(S.CONFIG_SIZE, CONFIG_SIZE);

// ------------------------------------------------------------- the fixture
const sha256 = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');

// A raw image of 6 MiB and a bit, pseudo-random (so gzip has work), with an
// empty config region (`WYRMCFG0` and zeros) at an offset that is no multiple
// of any chunk size.
const RAW_SIZE = 6 * 1024 * 1024 + 12345;
const OFFSET = 1024 * 1024 + 7;
function rawImage() {
  const raw = new Uint8Array(RAW_SIZE);
  let x = 0x2545f491;
  for (let i = 0; i < raw.length; i += 1) {
    x ^= x << 13; x ^= x >>> 17; x ^= x << 5;
    // runs of a byte, so the image compresses as a disk image does
    raw[i] = (i >> 9) % 3 === 0 ? 0 : x & 0xff;
  }
  raw.fill(0, OFFSET, OFFSET + CONFIG_SIZE);
  raw.set(Buffer.from('WYRMCFG0'), OFFSET);
  return raw;
}
const RAW = rawImage();
const GZ = new Uint8Array(zlib.gzipSync(RAW));

function entryFor(gz, raw = RAW) {
  return {
    board: 'qemu-armsr',
    file: 'wyrm-qemu-armsr-0.1.0-openwrt-25.12.6.img',
    size: raw.length,
    sha256: sha256(raw),
    config_offset: OFFSET,
    openwrt: '25.12.6',
    wyrmd: '0.1.0',
    manifest_sha256: 'ab'.repeat(32),
    download: { file: 'wyrm-qemu-armsr-0.1.0-openwrt-25.12.6.img.gz', size: gz.length, sha256: sha256(gz) },
    title: 'QEMU virt (arm64, tests only)',
    notes: 'For the smoke test.',
    lan: { bridge: 'br-lan', ports: ['eth0'] },
  };
}
const INDEX = JSON.stringify({ format: 'wyrm-images/1', images: [entryFor(GZ)] });
// the entry as the page has it: through the WebAssembly's check of the index
const ENTRY = wasm.check_index(INDEX)[0];
assert.equal(ENTRY.board, 'qemu-armsr');

const CATALOG = {
  links: [
    { id: 'modbus', form: 'builtin', driver: 'modbus', title: 'Modbus', category: 'Equipment', summary: 'Modbus TCP and RTU' },
    { id: 'scheduler', form: 'service', title: 'Scheduler', category: 'Apps' },
    { id: 'alarm', form: 'service', title: 'Alarms', category: 'Apps' },
    { id: 'dql', form: 'service', title: 'DQL', category: 'Apps' },
    { id: 'uplink', form: 'service', title: 'Uplink', category: 'Apps' },
  ],
};
const CHOICES = {
  format: 'wyrm-choices/1',
  site: 'plant',
  network: { mode: 'dhcp' },
  links: ['modbus', 'scheduler'],
  timezone: 'Europe/Kyiv',
  ntp: [],
};

function regionFor(choices = CHOICES) {
  const setup = wasm.new_setup(new Uint8Array(16).fill(7));
  try {
    return wasm.region_for(JSON.stringify(choices), JSON.stringify(ENTRY), JSON.stringify(CATALOG), setup.hash_hex);
  } finally {
    setup.free();
  }
}

// A Cache API that records what is written to it.
function fakeCaches() {
  const store = new Map();
  const log = { puts: 0, deletes: 0, opens: 0 };
  const cache = {
    async match(key) { const v = store.get(String(key)); return v ? new Response(v) : undefined; },
    async put(key, res) { log.puts += 1; store.set(String(key), new Uint8Array(await res.arrayBuffer())); },
    async delete(key) { log.deletes += 1; return store.delete(String(key)); },
    async keys() { return [...store.keys()].map((url) => ({ url })); },
  };
  return { caches: { async open() { log.opens += 1; return cache; } }, store, log };
}

// A fetch that serves `bytes` for the image and counts its calls.
function fakeFetch(bytes) {
  const calls = [];
  const fetch = async (url) => {
    calls.push(String(url));
    return new Response(new Blob([bytes]).stream(), { status: 200 });
  };
  return { fetch, calls };
}

async function withGlobals(globals, fn) {
  const saved = {};
  for (const k of Object.keys(globals)) {
    saved[k] = Object.getOwnPropertyDescriptor(globalThis, k);
    Object.defineProperty(globalThis, k, { value: globals[k], configurable: true, writable: true });
  }
  try {
    return await fn();
  } finally {
    for (const k of Object.keys(globals)) {
      if (saved[k]) Object.defineProperty(globalThis, k, saved[k]);
      else delete globalThis[k];
    }
  }
}

async function bytesOf(blob) {
  return new Uint8Array(await blob.arrayBuffer());
}

// One gzip member: the header, one deflate stream, the trailer, nothing after.
function oneMember(gz) {
  assert.equal(gz[0], 0x1f);
  assert.equal(gz[1], 0x8b);
  assert.equal(gz[2], 8, 'deflate');
  const flags = gz[3];
  let at = 10;
  if (flags & 4) at += 2 + (gz[at] | (gz[at + 1] << 8));
  if (flags & 8) while (gz[at++] !== 0);
  if (flags & 16) while (gz[at++] !== 0);
  if (flags & 2) at += 2;
  const { engine } = zlib.inflateRawSync(gz.subarray(at), { info: true });
  assert.equal(at + engine.bytesWritten + 8, gz.length, 'one gzip member, nothing after it');
  const view = new DataView(gz.buffer, gz.byteOffset, gz.byteLength);
  return view.getUint32(gz.length - 4, true);
}

// ------------------------------------------------------------------ tests
const tests = [];
const test = (name, fn) => tests.push({ name, fn });

test('a_download_that_does_not_match_is_refused', async () => {
  const cut = GZ.subarray(0, GZ.length - 1);
  const other = GZ.slice();
  other[100] ^= 0xff;
  for (const [what, bytes] of [['a short download', cut], ['a long download', Buffer.concat([GZ, Buffer.from([0])])], ['a changed download', other]]) {
    const c = fakeCaches();
    const f = fakeFetch(bytes);
    await withGlobals({ caches: c.caches, fetch: f.fetch }, async () => {
      await assert.rejects(S.fetchImage(ENTRY, () => {}), (e) => {
        assert.match(e.message, /does not match the published image/, what);
        assert.equal(e.retry, true, `${what}: the page offers to try again`);
        return true;
      });
    });
    assert.equal(c.log.puts, 0, `${what}: nothing is cached`);
    assert.equal(f.calls.length, 1);
    assert.equal(f.calls[0], 'images/' + ENTRY.download.file, `${what}: the page asks its own origin`);
  }

  // the right file: fetched once, cached, then served from the cache
  const c = fakeCaches();
  const f = fakeFetch(GZ);
  const seen = [];
  await withGlobals({ caches: c.caches, fetch: f.fetch }, async () => {
    const blob = await S.fetchImage(ENTRY, (got, total) => seen.push([got, total]));
    assert.equal(sha256(await bytesOf(blob)), ENTRY.download.sha256);
    assert.equal(c.log.puts, 1);
    assert.deepEqual(seen.at(-1), [GZ.length, GZ.length]);
    const again = await S.fetchImage(ENTRY, () => {});
    assert.equal(sha256(await bytesOf(again)), ENTRY.download.sha256);
    assert.equal(f.calls.length, 1, 'the second build takes the cached image');

    // a cached file that went bad is dropped and fetched again
    const [key] = c.store.keys();
    c.store.set(key, other);
    const fresh = await S.fetchImage(ENTRY, () => {});
    assert.equal(sha256(await bytesOf(fresh)), ENTRY.download.sha256);
    assert.equal(f.calls.length, 2);
    assert.equal(c.log.deletes, 1);
  });

  // storage that throws: the page downloads and goes on
  const g = fakeFetch(GZ);
  const broken = { async open() { throw new Error('SecurityError'); } };
  await withGlobals({ caches: broken, fetch: g.fetch }, async () => {
    const blob = await S.fetchImage(ENTRY, () => {});
    assert.equal(sha256(await bytesOf(blob)), ENTRY.download.sha256);
  });
  await withGlobals({ caches: undefined, fetch: g.fetch }, async () => {
    await S.fetchImage(ENTRY, () => {});
  });

  // a file name of the entry that is no plain name is never fetched
  const h = fakeFetch(GZ);
  await withGlobals({ caches: undefined, fetch: h.fetch }, async () => {
    for (const file of ['../x.img.gz', '//evil.example/x.img.gz', 'a/b.img.gz', '']) {
      const bad = { ...ENTRY, download: { ...ENTRY.download, file } };
      await assert.rejects(S.fetchImage(bad, () => {}));
    }
  });
  assert.equal(h.calls.length, 0);
});

test('assembly_replaces_only_the_region', async () => {
  const region = regionFor();
  assert.equal(region.length, CONFIG_SIZE);
  const blob = new Blob([GZ], { type: 'application/gzip' });
  const before = sha256(await bytesOf(blob));
  const out = await bytesOf(await S.assemble(blob, ENTRY, region));
  const isize = oneMember(out);
  assert.equal(isize, RAW_SIZE % 2 ** 32, 'ISIZE is the image size');
  const want = RAW.slice();
  want.set(region, OFFSET);
  const got = new Uint8Array(zlib.gunzipSync(out));
  assert.equal(got.length, RAW_SIZE);
  assert.ok(Buffer.compare(Buffer.from(got.subarray(0, OFFSET)), Buffer.from(RAW.subarray(0, OFFSET))) === 0, 'bytes before the region pass unchanged');
  assert.ok(Buffer.compare(Buffer.from(got.subarray(OFFSET + CONFIG_SIZE)), Buffer.from(RAW.subarray(OFFSET + CONFIG_SIZE))) === 0, 'bytes after the region pass unchanged');
  assert.equal(sha256(got), sha256(want));
  assert.equal(Buffer.from(got.subarray(OFFSET, OFFSET + 8)).toString(), 'WYRMCFG1');
  assert.equal(sha256(await bytesOf(blob)), before, 'the download is untouched');
});

test('a_download_of_the_wrong_length_is_refused', async () => {
  const region = regionFor();
  for (const raw of [RAW.subarray(0, RAW_SIZE - 1), Buffer.concat([RAW, Buffer.from([1, 2, 3])])]) {
    const blob = new Blob([zlib.gzipSync(raw)]);
    await assert.rejects(S.assemble(blob, ENTRY, region), /not the size of the published image/);
  }
  // an image that ends inside the region
  const blob = new Blob([zlib.gzipSync(RAW.subarray(0, OFFSET + 10))]);
  await assert.rejects(S.assemble(blob, ENTRY, region), /not the size of the published image/);
  // a region of another size is refused before anything is read
  await assert.rejects(S.assemble(new Blob([GZ]), ENTRY, region.subarray(1)));
});

test('assembly_streams', async () => {
  const region = regionFor();
  const want = RAW.slice();
  want.set(region, OFFSET);
  // Feeds RAW in chunks of `sizes` (cycled) and checks that each chunk is
  // handed on as it comes, of its own size, with nothing kept back.
  const run = (sizes) => {
    const t = S.regionTransformer(ENTRY, region);
    const out = [];
    let held = 0;
    const controller = {
      enqueue(chunk) { out.push(chunk); held -= 1; },
      error(e) { throw e; },
      terminate() {},
    };
    let at = 0;
    let i = 0;
    let inRegion = 0;
    while (at < RAW.length) {
      const n = Math.min(sizes[i % sizes.length], RAW.length - at);
      held += 1;
      t.transform(RAW.slice(at, at + n), controller);
      assert.equal(held, 0, `chunk ${i} was handed on at once, nothing kept back`);
      assert.equal(out.at(-1).length, n, 'one chunk out for one chunk in, of its size');
      if (at < OFFSET + CONFIG_SIZE && at + n > OFFSET) inRegion += 1;
      at += n;
      i += 1;
    }
    t.flush(controller);
    assert.equal(sha256(Buffer.concat(out)), sha256(want));
    return inRegion;
  };
  // small chunks of odd sizes: the region starts and ends inside one, and spans many
  assert.ok(run([1, 4093, 65536, 300000, 77, 65536]) > 20, 'the region spans many chunks');
  // one chunk that holds the whole region and more
  assert.equal(run([OFFSET - 5, CONFIG_SIZE + 10, 1 << 20]), 1);
});

test('the_file_name_is_plain', () => {
  assert.equal(S.fileName(ENTRY, 'plant'), 'wyrm-qemu-armsr-plant.img.gz');
  for (const site of ['../../etc/passwd', 'a b/c\\d', '<b>x</b>', 'Ünïcode', '.hidden', '']) {
    const name = S.fileName({ ...ENTRY, board: '../x y' }, site);
    assert.match(name, /^wyrm-[A-Za-z0-9_.-]+\.img\.gz$/, name);
    assert.ok(!name.includes('..'), name);
  }
});

// ------------------------------------------------------------- DOM stub
function makeDocument() {
  const byId = new Map();
  const node = (tag) => {
    const n = {
      tag, children: [], attrs: {}, style: { cssText: '' }, listeners: {}, parentNode: null,
      value: '', checked: false, disabled: false, hidden: false, innerHTML: '',
      setAttribute(k, v) {
        this.attrs[k] = String(v);
        if (k === 'id') byId.set(String(v), this);
        if (k === 'disabled') this.disabled = true;
        if (k === 'hidden') this.hidden = true;
        if (k === 'value') this.value = String(v);
        if (k === 'checked') this.checked = true;
      },
      getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; },
      removeAttribute(k) { delete this.attrs[k]; if (k === 'disabled') this.disabled = false; if (k === 'hidden') this.hidden = false; },
      addEventListener(k, f) { (this.listeners[k] = this.listeners[k] || []).push(f); },
      appendChild(c) { if (c.parentNode) c.parentNode.removeChild(c); c.parentNode = this; this.children.push(c); return c; },
      removeChild(c) { this.children.splice(this.children.indexOf(c), 1); c.parentNode = null; return c; },
      remove() { if (this.parentNode) this.parentNode.removeChild(this); },
      focus() {},
      click() { fire(this, 'click'); },
      get firstChild() { return this.children[0] || null; },
      get textContent() {
        return this.text !== undefined ? this.text : this.children.map((c) => c.textContent).join('');
      },
    };
    return n;
  };
  const body = node('body');
  const doc = {
    body,
    // what an element of the page with this id would be: null when there is none
    getElementById(id) { return byId.get(id) || null; },
    createElement: node,
    createElementNS(ns, tag) { return node(tag); },
    createTextNode(t) { const n = node('#text'); n.text = String(t); return n; },
  };
  // the containers of site/start/index.html
  for (const id of ['start-status', 'start-none', 'start-steps', 'st-boards', 'st-site', 'st-network', 'st-links', 'st-time', 'st-ssh', 'st-build']) {
    body.appendChild(doc.createElement('div')).setAttribute('id', id);
  }
  return { doc, byId };
}

function fire(n, kind) {
  for (const f of n.listeners[kind] || []) f({ type: kind, target: n, preventDefault() {} });
}

// whether `n` is shown: neither it nor a parent is hidden, and it is in the page
function shown(n) {
  for (let p = n; p; p = p.parentNode) {
    if (p.hidden) return false;
    if (p.tag === 'body') return true;
  }
  return false;
}

function find(root, pred) {
  if (pred(root)) return root;
  for (const c of root.children) {
    const r = find(c, pred);
    if (r) return r;
  }
  return null;
}

// Storage that throws on every use: the page must neither need it nor touch it.
const NO_STORAGE = new Proxy({}, { get() { throw new Error('storage is not for this page'); } });

// A wasm whose calls are counted.
function spyWasm() {
  const calls = { new_setup: 0, region_for: 0, check_choices: 0, freed: 0 };
  const spy = {
    check_index: wasm.check_index,
    check_choices(...a) { calls.check_choices += 1; return wasm.check_choices(...a); },
    region_for(...a) { calls.region_for += 1; return wasm.region_for(...a); },
    new_setup(r) {
      calls.new_setup += 1;
      const s = wasm.new_setup(r);
      const free = s.free.bind(s);
      s.free = () => { calls.freed += 1; free(); };
      return s;
    },
  };
  return { spy, calls };
}

function mountPage() {
  const { doc, byId } = makeDocument();
  const { spy, calls } = spyWasm();
  S.mount(doc, spy, [ENTRY], CATALOG);
  return { doc, byId, calls };
}

function typeInto(byId, id, value) {
  const input = byId.get(id);
  assert.ok(input, `the page has #${id}`);
  input.value = value;
  fire(input, 'input');
  fire(input, 'change');
}

test('the_download_waits_for_the_confirmation', async () => {
  await withGlobals({ localStorage: NO_STORAGE, sessionStorage: NO_STORAGE }, async () => {
    const { doc, byId, calls } = mountPage();
    typeInto(byId, 'st-site-name', 'plant');
    const download = () => byId.get('st-download');
    assert.ok(!download() || !shown(download()) || download().disabled, 'no download before a build');

    byId.get('st-build-button').click();
    assert.equal(calls.new_setup, 1);
    assert.equal(calls.freed, 1, 'the setup is freed once the code is shown');
    const panel = byId.get('st-code');
    assert.ok(panel && shown(panel), 'the code is shown');
    const text = panel.textContent;
    const warn = text.indexOf('Write this code down. It is shown once and is not stored anywhere.');
    assert.ok(warn >= 0, 'the page says the code is shown once');
    const code = byId.get('st-code-text').textContent.replace(/\s/g, '');
    assert.match(code, /^[A-Z2-7]{4}(-?[A-Z2-7]{1,4})+$/);
    assert.ok(warn < text.indexOf(byId.get('st-code-text').textContent), 'the warning comes before the code');
    assert.match(byId.get('st-code-qr').innerHTML, /^<svg /);

    const box = byId.get('st-wrote-it');
    assert.ok(box && shown(box));
    assert.match(find(doc.body, (n) => n.tag === 'label' && n.attrs.for === 'st-wrote-it').textContent, /I wrote it down/);
    assert.ok(shown(download()) && download().disabled, 'Download is off until the checkbox');
    box.checked = true;
    fire(box, 'change');
    assert.equal(download().disabled, false, 'Download is on after the checkbox');
    box.checked = false;
    fire(box, 'change');
    assert.equal(download().disabled, true, 'and off again without it');

    // a choice changed after the build: the code and its region are gone
    box.checked = true;
    fire(box, 'change');
    typeInto(byId, 'st-site-name', 'plant2');
    assert.ok(!shown(byId.get('st-code-text')) || byId.get('st-code-text').textContent === '', 'the old code is gone');
    assert.ok(!shown(download()) || download().disabled, 'no download of the old choices');
  });
});

test('a_refused_site_shows_the_device_words_and_no_download', async () => {
  await withGlobals({ localStorage: NO_STORAGE, sessionStorage: NO_STORAGE }, async () => {
    for (const site of ['.hidden', 'a b', 'x'.repeat(65), '']) {
      const { byId, calls } = mountPage();
      typeInto(byId, 'st-site-name', site);
      byId.get('st-build-button').click();
      const err = byId.get('st-site-name-error');
      assert.ok(err && shown(err), `${JSON.stringify(site)}: an error at the site field`);
      assert.match(err.textContent, /names no site a board takes/, 'in the device\'s words');
      assert.equal(calls.new_setup, 0, 'no setup code is made');
      const panel = byId.get('st-code');
      assert.ok(!panel || !shown(panel) || panel.textContent === '', 'no code shown');
      const download = byId.get('st-download');
      assert.ok(!download || !shown(download) || download.disabled, 'no download');
    }
    // a static address the device refuses: shown at the address
    const { byId, calls } = mountPage();
    byId.get('st-net-static').click();
    typeInto(byId, 'st-address', '192.168.1.0');
    typeInto(byId, 'st-prefix', '24');
    byId.get('st-build-button').click();
    assert.match(byId.get('st-address-error').textContent, /`192\.168\.1\.0` is refused/);
    assert.equal(calls.new_setup, 0);
  });
});

// --------------------------------------------------------------------- run
let failed = 0;
for (const t of tests) {
  try {
    await t.fn();
    console.log(`ok   ${t.name}`);
  } catch (e) {
    failed += 1;
    console.error(`FAIL ${t.name}\n${e.stack || e}`);
  }
}
if (failed) {
  console.error(`start: ${failed} of ${tests.length} tests failed`);
  process.exit(1);
}
console.log(`start: ${tests.length} tests passed`);
