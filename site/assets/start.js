// The image builder page (site/start/index.html, ADR 0051 §4).
//
// The person picks a board, a site, the network, the links, the time zone,
// NTP and an SSH key. The WebAssembly of crates/wyrm-image-web turns the
// choices into the 4 MiB config region (the same code `wyr image build
// --choices` runs) and makes the one-time setup code. This script fetches the
// board's base image from this site, checks it against the index, and streams
// it: gunzip, the region's bytes replaced, gzip again, into a file to save.
//
// Nothing leaves the browser: the page asks its own origin for the index, the
// catalog of links and the image, and nothing else. It writes nothing to
// localStorage, sessionStorage or the URL; the only thing it keeps is the
// checked base image, in the Cache API, so a second build does not download
// it again. Every text goes into the page as a text node.
//
// Under Node (tool/site/test_start.mjs) the script does not touch a DOM: it
// hands its functions over as `globalThis.wyrmStart`.
(function (global) {
  'use strict';

  // The size of the config region (wyrm_image::CONFIG_SIZE).
  var CONFIG_SIZE = 4 * 1024 * 1024;
  // Where the index, the catalog and the images are, beside the page.
  var IMAGES = 'images/';
  // The Cache API store of checked base images, keyed by their SHA-256.
  var CACHE = 'wyrm-start-images';
  var CHOICES_FORMAT = 'wyrm-choices/1';
  var MIB = 1024 * 1024;

  var MSG = {
    mismatch: 'The download does not match the published image (its size or its SHA-256 is another). It may have been cut, or the images changed since this page opened. Reload the page and try again.',
    length: 'The unpacked image is not the size of the published image. Reload the page and try again.',
    entry: 'This board\'s entry in the index names no image this page can fetch.',
    region: 'The configuration is not one region of 4 MiB.'
  };

  // A refusal the person can do something about: try again.
  function Refused(message) {
    var e = new Error(message);
    e.retry = true;
    return e;
  }

  // The error of work that was called off (`signal` aborted): a download or an
  // assembly that a new build or a changed choice voided.
  function Aborted() {
    var e = new Error('The download was called off.');
    e.name = 'AbortError';
    return e;
  }
  function stopped(signal) {
    if (signal && signal.aborted) throw Aborted();
  }

  function plainName(name) {
    return typeof name === 'string' && /^[A-Za-z0-9_][A-Za-z0-9_.+-]*$/.test(name) && name.indexOf('..') < 0;
  }

  function hex(buffer) {
    var b = new Uint8Array(buffer);
    var out = '';
    for (var i = 0; i < b.length; i += 1) out += (b[i] < 16 ? '0' : '') + b[i].toString(16);
    return out;
  }

  // Whether `bytes` are those of the download the entry names.
  async function matches(bytes, dl) {
    if (bytes.length !== dl.size) return false;
    return hex(await global.crypto.subtle.digest('SHA-256', bytes)) === dl.sha256;
  }

  // The cache of base images, or null when the browser refuses storage
  // (a private window, a full disk): the page then just downloads.
  async function openCache() {
    try {
      return global.caches ? await global.caches.open(CACHE) : null;
    } catch (e) {
      return null;
    }
  }

  function cacheKey(sha) {
    return IMAGES + 'sha256/' + sha;
  }

  // The base image of `entry` as a Blob (gzip), checked against
  // `entry.download` (size, SHA-256). From the cache when it holds it,
  // else from this site. `onProgress(bytes, total)` follows the download;
  // `signal` (an AbortSignal) calls it off: the request and its body stop.
  async function fetchImage(entry, onProgress, signal) {
    var dl = entry && entry.download;
    if (!dl || !plainName(dl.file) || !Number.isSafeInteger(dl.size) || dl.size <= 0 ||
        !/^[0-9a-f]{64}$/.test(dl.sha256)) {
      throw new Error(MSG.entry);
    }
    var progress = typeof onProgress === 'function' ? onProgress : function () {};
    var key = cacheKey(dl.sha256);
    var cache = await openCache();
    if (cache) {
      try {
        var hit = await cache.match(key);
        if (hit) {
          var kept = new Uint8Array(await hit.arrayBuffer());
          if (await matches(kept, dl)) {
            progress(dl.size, dl.size);
            return new Blob([kept], { type: 'application/gzip' });
          }
          await cache.delete(key);
        }
      } catch (e) {
        // a cache that fails to read is a cache that is empty
      }
    }

    stopped(signal);
    var res;
    try {
      res = await global.fetch(IMAGES + encodeURIComponent(dl.file), { cache: 'no-store', signal: signal });
    } catch (e) {
      stopped(signal);
      throw Refused('The image could not be downloaded: ' + message(e) + '. Check the connection and try again.');
    }
    if (!res.ok || !res.body) {
      throw Refused('The image could not be downloaded (HTTP ' + res.status + '). Try again.');
    }
    // The download goes into one buffer of the size the index says: a longer
    // one is refused as soon as it passes that size.
    var buf = new Uint8Array(dl.size);
    var got = 0;
    var reader = res.body.getReader();
    for (;;) {
      var step;
      try {
        step = await reader.read();
      } catch (e) {
        stopped(signal);
        throw Refused('The download stopped: ' + message(e) + '. Try again.');
      }
      if (signal && signal.aborted) {
        try { await reader.cancel(); } catch (e) { /* called off anyway */ }
        throw Aborted();
      }
      if (step.done) break;
      var chunk = step.value;
      if (got + chunk.length > dl.size) {
        try { await reader.cancel(); } catch (e) { /* the refusal below says it */ }
        throw Refused(MSG.mismatch);
      }
      buf.set(chunk, got);
      got += chunk.length;
      progress(got, dl.size);
    }
    if (!(await matches(buf.subarray(0, got), dl))) throw Refused(MSG.mismatch);
    var blob = new Blob([buf], { type: 'application/gzip' });
    if (cache) {
      try {
        await cache.put(key, new Response(blob));
      } catch (e) {
        // not kept: the next build downloads again
      }
    }
    return blob;
  }

  // Drops the cached images that no offered entry names any more.
  async function pruneCache(entries) {
    var cache = await openCache();
    if (!cache || !cache.keys) return;
    try {
      var keep = {};
      entries.forEach(function (e) { if (e.download) keep[e.download.sha256] = true; });
      var keys = await cache.keys();
      for (var i = 0; i < keys.length; i += 1) {
        var m = /sha256\/([0-9a-f]{64})$/.exec(keys[i].url);
        if (!m || !keep[m[1]]) await cache.delete(keys[i]);
      }
    } catch (e) {
      // nothing to tidy then
    }
  }

  // The replace step of the assembly, as a TransformStream's transformer: the
  // raw image streams through it, and the bytes [config_offset,
  // config_offset + CONFIG_SIZE) become `region`. Each chunk is handed on as
  // it comes (a copy only when it touches the region); nothing is kept but
  // the count. The image must be exactly `entry.size` bytes long.
  function regionTransformer(entry, region, onProgress) {
    if (!(region instanceof Uint8Array) || region.length !== CONFIG_SIZE) throw new Error(MSG.region);
    var size = entry.size;
    var start = entry.config_offset;
    var end = start + CONFIG_SIZE;
    if (!Number.isSafeInteger(size) || !Number.isSafeInteger(start) || start < 0 || end > size) {
      throw new Error(MSG.entry);
    }
    var pos = 0;
    var written = 0;
    var progress = typeof onProgress === 'function' ? onProgress : function () {};
    return {
      transform: function (chunk, controller) {
        var a = pos;
        var b = pos + chunk.length;
        pos = b;
        if (b > size) throw Refused(MSG.length);
        var lo = Math.max(a, start);
        var hi = Math.min(b, end);
        if (lo < hi) {
          var copy = new Uint8Array(chunk);
          copy.set(region.subarray(lo - start, hi - start), lo - a);
          written += hi - lo;
          chunk = copy;
        }
        controller.enqueue(chunk);
        progress(pos, size);
      },
      flush: function () {
        if (pos !== size || written !== CONFIG_SIZE) throw Refused(MSG.length);
      }
    };
  }

  // The finished image: `blob` (the checked base image, one gzip member)
  // unpacked, the region written, packed again as one gzip member. Neither
  // the raw image nor the download is changed or held whole: the bytes
  // stream through, and the result is gathered as the parts of a Blob.
  // `signal` calls it off: the stream is cancelled and nothing is kept.
  async function assemble(blob, entry, region, onProgress, signal) {
    stopped(signal);
    var replace = new TransformStream(regionTransformer(entry, region, onProgress));
    var out = blob.stream()
      .pipeThrough(new global.DecompressionStream('gzip'))
      .pipeThrough(replace)
      .pipeThrough(new global.CompressionStream('gzip'));
    var parts = [];
    var reader = out.getReader();
    var cancel = function () { reader.cancel(Aborted()).catch(function () {}); };
    if (signal) signal.addEventListener('abort', cancel);
    try {
      for (;;) {
        var step = await reader.read();
        stopped(signal);
        if (step.done) break;
        parts.push(step.value);
      }
    } catch (e) {
      parts = null;
      stopped(signal);
      throw e;
    } finally {
      if (signal) signal.removeEventListener('abort', cancel);
    }
    return new Blob(parts, { type: 'application/gzip' });
  }

  // The name of the finished file: `wyrm-<board>-<site>.img.gz`, of
  // `A-Z a-z 0-9 _ . -` only.
  function fileName(entry, site) {
    var clean = function (s) {
      var t = String(s === undefined || s === null ? '' : s)
        .replace(/[^A-Za-z0-9_.-]+/g, '-')
        .replace(/\.{2,}/g, '.')
        .replace(/^[.-]+|[.-]+$/g, '');
      return t || 'site';
    };
    return 'wyrm-' + clean(entry.board) + '-' + clean(site) + '.img.gz';
  }

  // ------------------------------------------------------------------ page
  var ACCENT = '#E8893A';
  var MONO = "font-family: 'IBM Plex Mono', monospace; ";
  var CATEGORIES = ['Equipment', 'File stores', 'History sync', 'Apps', 'Messaging', 'Test'];
  var INPUT = 'box-sizing: border-box; width: 100%; height: 46px; padding: 0 14px; border-radius: 10px; border: 1px solid #3A4249; background: #161A1D; color: #ECE9E1; font-size: 16px; ';
  var LABEL = 'font-size: 15px; font-weight: 600';
  var HINT = 'font-size: 13px; line-height: 1.5; color: #8E979C';
  var ERROR = 'font-size: 14px; line-height: 1.5; color: #F3A766';
  var CARD = 'padding: 20px; border-radius: 12px; background: #161A1D; border: 1px solid #252B30; ';

  function mib(n) { return (Math.round(n / MIB * 10) / 10).toFixed(1) + ' MiB'; }

  function message(e) {
    if (e && typeof e.message === 'string') return e.message;
    return String(e);
  }

  // Which field a refusal of the choices is about, from its sentence
  // (crates/wyrm-image: ChoicesError, ImageError).
  function fieldOf(text, values) {
    var m = /^`([^`]*)` is refused/.exec(text);
    if (m) {
      // the choices carry the trimmed fields, so the sentence names them trimmed
      var trimmed = function (v) { return String(v === undefined || v === null ? '' : v).trim(); };
      if (trimmed(values.address) === m[1]) return 'address';
      if (trimmed(values.gateway) === m[1]) return 'gateway';
      return 'dns';
    }
    if (/\bprefix\b/.test(text)) return 'prefix';
    if (/^the link `/.test(text)) return 'links';
    if (/network ports|choose DHCP|`lan`/.test(text)) return 'network';
    if (/\bsite\b/.test(text)) return 'site-name';
    if (/`timezone`/.test(text)) return 'timezone';
    if (/`ntp`/.test(text)) return 'ntp';
    return 'build';
  }

  // The page itself, in `doc`, with the WebAssembly `wasm`, the offered
  // `entries` of the index and the `catalog` of links.
  function mount(doc, wasm, entries, catalog) {
    function el(tag, attrs, kids) {
      var n = doc.createElement(tag);
      for (var k in attrs || {}) {
        var v = attrs[k];
        if (v === null || v === undefined || v === false) continue;
        if (k === 'style') n.style.cssText = v;
        else if (k === 'onclick') n.addEventListener('click', v);
        else n.setAttribute(k, v === true ? '' : v);
      }
      add(n, kids);
      return n;
    }
    function add(n, kids) {
      if (kids === null || kids === undefined) return;
      if (!Array.isArray(kids)) kids = [kids];
      kids.forEach(function (c) {
        if (c === null || c === undefined || c === false) return;
        if (Array.isArray(c)) add(n, c);
        else n.appendChild(typeof c === 'object' ? c : doc.createTextNode(String(c)));
      });
    }
    function clear(n) {
      while (n.firstChild) n.removeChild(n.firstChild);
      return n;
    }
    function fill(id, kids) {
      var n = doc.getElementById(id);
      if (!n) return null;
      clear(n);
      add(n, kids);
      return n;
    }
    function code(text) { return el('code', null, text); }
    function pressed(n, on) {
      n.setAttribute('aria-pressed', on ? 'true' : 'false');
      n.style.borderColor = on ? ACCENT : '#2A3136';
      n.style.background = on ? '#1B2025' : '#161A1D';
    }

    var links = (catalog && Array.isArray(catalog.links)) ? catalog.links : [];
    var catalogJson = JSON.stringify({ links: links });
    var browserZone = 'UTC';
    try {
      browserZone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
    } catch (e) { /* UTC then */ }

    var st = {
      board: entries[0].board,
      site: 'plant',
      mode: 'dhcp',
      address: '', prefix: '24', gateway: '', dns: '',
      // the broker's own links are on, as wyrmd has them by default
      links: links.filter(function (l) { return l.form === 'service'; }).map(function (l) { return l.id; }),
      timezone: browserZone,
      ntp: '',
      ssh: '',
      built: null,
      busy: false
    };

    function entry() {
      return entries.filter(function (e) { return e.board === st.board; })[0];
    }
    function words(text) {
      return String(text).split(/[\s,]+/).filter(function (w) { return w; });
    }
    function choices() {
      var net = { mode: 'dhcp' };
      if (st.mode === 'static') {
        var p = /^\s*\d{1,3}\s*$/.test(st.prefix) ? Number(st.prefix) : 0;
        // a prefix that is no number 0 to 255 gets the device's sentence for prefixes
        net = { mode: 'static', address: st.address.trim(), prefix: p > 255 ? 0 : p, dns: words(st.dns) };
        if (st.gateway.trim()) net.gateway = st.gateway.trim();
      }
      var c = {
        format: CHOICES_FORMAT,
        site: st.site,
        network: net,
        links: st.links.slice(),
        timezone: st.timezone,
        ntp: words(st.ntp)
      };
      if (st.ssh.trim()) c.ssh_keys = st.ssh;
      return c;
    }

    // ---- errors at their fields
    var errorIds = ['site-name', 'network', 'address', 'prefix', 'gateway', 'dns', 'links', 'timezone', 'ntp', 'build', 'download'];
    function clearErrors() {
      errorIds.forEach(function (f) {
        var n = doc.getElementById('st-' + f + '-error');
        if (n) { clear(n); n.hidden = true; }
        var i = doc.getElementById('st-' + f);
        if (i && formControl(i)) i.removeAttribute('aria-invalid');
      });
    }
    function showError(field, text) {
      var n = doc.getElementById('st-' + field + '-error');
      if (!n) n = doc.getElementById('st-build-error');
      clear(n);
      add(n, text);
      n.hidden = false;
      var i = doc.getElementById('st-' + field);
      if (i && formControl(i)) {
        i.setAttribute('aria-invalid', 'true');
        i.focus();
      }
    }
    function formControl(n) {
      return /^(input|select|textarea)$/i.test(n.tagName || n.tag || '');
    }
    function errorSpan(field) {
      return el('span', { id: 'st-' + field + '-error', role: 'alert', hidden: true, style: ERROR });
    }

    // A change of any choice voids a build: its code and region go, and the
    // person builds again (with a new code).
    function changed() {
      if (st.built) {
        // a download or an assembly of the old choices stops here
        if (st.built.abort) st.built.abort.abort();
        st.built = null;
        clear(doc.getElementById('st-code'));
        doc.getElementById('st-code').hidden = true;
        fill('st-after', null);
        doc.getElementById('st-after').hidden = true;
        var note = doc.getElementById('st-build-note');
        clear(note);
        add(note, 'Your choices changed: build again. The image gets a new code.');
        note.hidden = false;
      }
    }
    function input(id, value, attrs, onValue) {
      var a = { id: id, type: 'text', autocomplete: 'off', spellcheck: 'false', style: INPUT + MONO };
      for (var k in attrs || {}) a[k] = attrs[k];
      var n = el(a.type === 'textarea' ? 'textarea' : 'input', a);
      n.value = value;
      n.addEventListener('input', function () { onValue(n.value); changed(); });
      return n;
    }
    function field(id, label, control, hint) {
      return el('div', { style: 'display: flex; flex-direction: column; gap: 8px; min-width: 0' }, [
        el('label', { for: id, style: LABEL }, label),
        control,
        hint ? el('span', { style: HINT }, hint) : null,
        errorSpan(id.replace(/^st-/, ''))
      ]);
    }

    // ---- 1 Board
    var boardButtons = entries.map(function (e) {
      var b = el('button', {
        type: 'button', 'data-board': e.board,
        style: 'text-align: left; padding: 20px; border-radius: 12px; border: 1px solid #2A3136; background: #161A1D; color: #ECE9E1; display: flex; flex-direction: column; gap: 8px; min-width: 0',
        onclick: function () {
          if (st.board === e.board) return;
          st.board = e.board;
          boardButtons.forEach(function (x) { pressed(x, x.getAttribute('data-board') === st.board); });
          if (!entry().lan && st.mode === 'static') setMode('dhcp');
          networkState();
          changed();
        }
      }, [
        el('span', { style: 'font-size: 18px; font-weight: 600' }, e.title || e.board),
        e.notes ? el('span', { style: 'font-size: 14px; line-height: 1.55; color: #A3ABAF' }, e.notes) : null,
        el('span', { style: MONO + 'font-size: 12px; color: #8E979C' },
          e.board + ' · download ' + mib(e.download.size) + ' · image ' + mib(e.size)),
        el('span', { style: MONO + 'font-size: 12px; color: #8E979C' }, 'OpenWrt ' + e.openwrt + ' · wyrmd ' + e.wyrmd)
      ]);
      pressed(b, e.board === st.board);
      return b;
    });
    fill('st-boards', boardButtons);

    // ---- 2 Site
    fill('st-site', field('st-site-name', 'Site name',
      input('st-site-name', st.site, { maxlength: '64', 'aria-describedby': 'st-site-hint' }, function (v) { st.site = v; }),
      'Every key of this broker starts with wy/<site>/. 1 to 64 of A-Z a-z 0-9 _ . -, not starting with a dot.'));

    // ---- 3 Network
    var dhcpBtn = el('button', { id: 'st-net-dhcp', type: 'button', style: 'min-height: 44px; padding: 8px 18px; border-radius: 999px; border: 1px solid #2A3136; color: #ECE9E1; font-size: 14px', onclick: function () { setMode('dhcp'); changed(); } }, 'DHCP');
    var staticBtn = el('button', { id: 'st-net-static', type: 'button', style: 'min-height: 44px; padding: 8px 18px; border-radius: 999px; border: 1px solid #2A3136; color: #ECE9E1; font-size: 14px', onclick: function () { if (entry().lan) { setMode('static'); changed(); } } }, 'Static address');
    var staticBox = el('div', { id: 'st-static', hidden: true, style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px' }, [
      field('st-address', 'Address', input('st-address', st.address, { inputmode: 'decimal', placeholder: '192.168.1.20' }, function (v) { st.address = v; })),
      field('st-prefix', 'Prefix length', input('st-prefix', st.prefix, { inputmode: 'numeric', placeholder: '24' }, function (v) { st.prefix = v; }), '24 is 255.255.255.0'),
      field('st-gateway', 'Gateway (optional)', input('st-gateway', st.gateway, { inputmode: 'decimal', placeholder: '192.168.1.1' }, function (v) { st.gateway = v; })),
      field('st-dns', 'DNS servers (optional)', input('st-dns', st.dns, { placeholder: '192.168.1.1, 9.9.9.9' }, function (v) { st.dns = v; }))
    ]);
    var netNote = el('span', { style: HINT });
    function setMode(mode) {
      st.mode = mode;
      pressed(dhcpBtn, mode === 'dhcp');
      pressed(staticBtn, mode === 'static');
      staticBox.hidden = mode !== 'static';
    }
    function networkState() {
      var lan = entry().lan;
      staticBtn.disabled = !lan;
      clear(netNote);
      add(netNote, lan
        ? 'DHCP: the device asks your network for its address. A static address goes on the board\'s LAN ports.'
        : 'This board\'s image does not say which network ports it has: it takes its address from DHCP.');
    }
    fill('st-network', [
      el('div', { role: 'group', 'aria-label': 'Network', style: 'display: flex; flex-wrap: wrap; gap: 10px' }, [dhcpBtn, staticBtn]),
      netNote,
      errorSpan('network'),
      staticBox
    ]);
    setMode('dhcp');
    networkState();

    // ---- 4 Links
    var cats = CATEGORIES.slice();
    links.forEach(function (l) { var c = l.category || 'Other'; if (cats.indexOf(c) < 0) cats.push(c); });
    fill('st-links', [
      links.length ? null : el('span', { style: HINT }, 'This image offers no links to choose. More can be installed from Studio once the broker runs.'),
      cats.map(function (c) {
        var items = links.filter(function (l) { return (l.category || 'Other') === c; });
        if (!items.length) return null;
        return el('div', { role: 'group', 'aria-label': c, style: 'display: flex; flex-direction: column; gap: 10px' }, [
          el('span', { style: MONO + 'font-size: 13px; letter-spacing: 0.06em; text-transform: uppercase; color: #8E979C' }, c),
          el('div', { style: 'display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 240px), 1fr)); gap: 10px' }, items.map(function (l) {
            var mark = el('span', { 'aria-hidden': 'true', style: 'flex: 0 0 auto; width: 16px; height: 16px; margin-top: 3px; border-radius: 4px; border: 1.5px solid #4A535A' });
            var b = el('button', {
              type: 'button', 'data-link': l.id,
              style: 'text-align: left; min-height: 64px; padding: 12px 14px; border-radius: 10px; border: 1px solid #2A3136; background: #161A1D; color: #ECE9E1; display: flex; gap: 12px; align-items: flex-start; min-width: 0',
              onclick: function () {
                var i = st.links.indexOf(l.id);
                if (i >= 0) st.links.splice(i, 1); else st.links.push(l.id);
                show();
                changed();
              }
            }, [
              mark,
              el('span', { style: 'flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 3px' }, [
                el('span', { style: 'font-size: 15px; font-weight: 600' }, l.title || l.id),
                l.summary ? el('span', { style: 'font-size: 13px; line-height: 1.45; color: #A3ABAF' }, l.summary) : null,
                el('span', { style: MONO + 'font-size: 12px; color: #8E979C' },
                  l.form === 'service' ? 'in the broker' : l.form === 'builtin' ? 'built-in driver' : 'package, installed at the first start')
              ])
            ]);
            function show() {
              var on = st.links.indexOf(l.id) >= 0;
              pressed(b, on);
              mark.style.borderColor = on ? ACCENT : '#4A535A';
              mark.style.background = on ? ACCENT : 'transparent';
            }
            show();
            return b;
          }))
        ]);
      }),
      errorSpan('links')
    ]);

    // ---- 5 Time
    var zones = [];
    try {
      zones = Intl.supportedValuesOf('timeZone');
    } catch (e) { /* a text field then */ }
    var zoneControl;
    if (zones.length) {
      if (zones.indexOf('UTC') < 0) zones = ['UTC'].concat(zones);
      if (zones.indexOf(st.timezone) < 0) zones = [st.timezone].concat(zones);
      zoneControl = el('select', { id: 'st-timezone', style: INPUT }, zones.map(function (z) {
        return el('option', { value: z, selected: z === st.timezone }, z);
      }));
      zoneControl.value = st.timezone;
      zoneControl.addEventListener('change', function () { st.timezone = zoneControl.value; changed(); });
    } else {
      zoneControl = input('st-timezone', st.timezone, { placeholder: 'Europe/Kyiv' }, function (v) { st.timezone = v; });
    }
    fill('st-time', el('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); gap: 20px' }, [
      field('st-timezone', 'Time zone', zoneControl, 'This browser\'s zone is chosen.'),
      field('st-ntp', 'NTP servers (optional)', input('st-ntp', st.ntp, { placeholder: 'ntp.example.org, 192.168.1.1' }, function (v) { st.ntp = v; }),
        'Without them, the device uses those of DHCP, then the OpenWrt pool. At most 16.')
    ]));

    // ---- 6 SSH
    fill('st-ssh', field('st-ssh-keys', 'SSH public keys for root (optional)',
      input('st-ssh-keys', st.ssh, { type: 'textarea', rows: '3', placeholder: 'ssh-ed25519 AAAA… you@laptop', style: INPUT + MONO + 'height: auto; min-height: 92px; padding: 12px 14px; resize: vertical' }, function (v) { st.ssh = v; }),
      'Without a key, the device has no SSH login. Only the public key goes in.'));

    // ---- 7 Build
    var buildBtn = el('button', {
      id: 'st-build-button', type: 'button',
      style: 'align-self: flex-start; min-height: 48px; padding: 10px 24px; border-radius: 10px; border: 1px solid ' + ACCENT + '; background: ' + ACCENT + '; color: #0E1113; font-size: 16px; font-weight: 600',
      onclick: build
    }, 'Build');
    fill('st-build', [
      buildBtn,
      el('span', { id: 'st-build-note', hidden: true, style: HINT }),
      errorSpan('build'),
      el('div', { id: 'st-code', hidden: true, style: 'display: flex; flex-direction: column; gap: 18px' }),
      el('div', { id: 'st-after', hidden: true, style: 'display: flex; flex-direction: column; gap: 16px' })
    ]);

    function build() {
      clearErrors();
      changed();
      var note = doc.getElementById('st-build-note');
      note.hidden = true;
      var e = entry();
      var c = choices();
      var choicesJson = JSON.stringify(c);
      var entryJson = JSON.stringify(e);
      try {
        wasm.check_choices(choicesJson, entryJson, catalogJson);
      } catch (err) {
        var text = message(err);
        showError(fieldOf(text, st), text);
        return;
      }
      var setup = null;
      var shownCode;
      var qr;
      var region;
      try {
        setup = wasm.new_setup(global.crypto.getRandomValues(new Uint8Array(16)));
        region = wasm.region_for(choicesJson, entryJson, catalogJson, setup.hash_hex);
        shownCode = setup.code;
        qr = setup.qr_svg;
      } catch (err) {
        showError('build', message(err));
        return;
      } finally {
        // the code stays in the page's text only
        if (setup) setup.free();
      }
      st.built = { entry: e, site: c.site, region: region };
      showCode(shownCode, qr);
    }

    function showCode(text, qr) {
      var qrBox = el('div', { id: 'st-code-qr', role: 'img', 'aria-label': 'The setup code as a QR code', style: 'width: 168px; height: 168px; padding: 10px; border-radius: 8px; background: #ECE9E1; color: #0E1113; flex: 0 0 auto' });
      // the SVG is made by the WebAssembly (crates/wyrm-image-web, `qr_svg`): numbers and
      // fixed markup only, nothing a person typed
      qrBox.innerHTML = qr;
      var box = el('input', { id: 'st-wrote-it', type: 'checkbox', style: 'width: 20px; height: 20px; margin: 0; accent-color: ' + ACCENT });
      var dl = el('button', {
        id: 'st-download', type: 'button', disabled: true,
        style: 'align-self: flex-start; min-height: 48px; padding: 10px 24px; border-radius: 10px; border: 1px solid #6CC4B0; background: transparent; color: #ECE9E1; font-size: 16px; font-weight: 600',
        onclick: download
      }, 'Download ' + fileName(st.built.entry, st.built.site));
      box.addEventListener('change', function () { dl.disabled = !box.checked || st.busy; });
      var panel = fill('st-code', [
        el('p', { role: 'note', style: 'margin: 0; padding: 14px 18px; border-radius: 12px; border: 1px solid #5A4330; background: #161A1D; font-size: 15px; line-height: 1.6; color: #ECE9E1' }, [
          el('strong', null, 'Write this code down. It is shown once and is not stored anywhere.'),
          ' The image holds only its hash. Whoever has the code makes the first admin of this broker: keep it apart from the card.'
        ]),
        el('div', { style: 'display: flex; flex-wrap: wrap; gap: 20px; align-items: center' }, [
          el('div', { style: 'flex: 1 1 260px; min-width: 0; display: flex; flex-direction: column; gap: 8px' }, [
            el('span', { style: MONO + 'font-size: 13px; color: #8E979C' }, 'setup code'),
            // the groups break between lines only after a dash
            el('p', { id: 'st-code-text', style: 'margin: 0; ' + MONO + 'font-size: 22px; line-height: 1.5; font-weight: 600; letter-spacing: 0.08em; color: #ECE9E1' },
              text.split('-').map(function (g, i, all) {
                return el('span', { style: 'white-space: nowrap' }, g + (i < all.length - 1 ? '-' : ''));
              })),
            el('span', { style: HINT }, 'It makes the first admin of the broker. Lower case, spaces and dashes do not matter.')
          ]),
          qrBox
        ]),
        el('div', { style: 'display: flex; gap: 10px; align-items: center' }, [
          box,
          el('label', { for: 'st-wrote-it', style: 'font-size: 15px; font-weight: 600' }, 'I wrote it down')
        ]),
        dl,
        el('div', { id: 'st-progress-box', hidden: true, style: 'display: flex; flex-direction: column; gap: 6px; max-width: 560px' }, [
          el('progress', { id: 'st-progress', max: '1', value: '0', style: 'width: 100%; height: 10px; accent-color: ' + ACCENT }),
          el('span', { id: 'st-progress-text', 'aria-live': 'polite', style: MONO + 'font-size: 13px; color: #A3ABAF' })
        ]),
        errorSpan('download')
      ]);
      panel.hidden = false;
    }

    function progress(label, got, total) {
      var bar = doc.getElementById('st-progress');
      bar.max = total;
      bar.value = got;
      var t = doc.getElementById('st-progress-text');
      clear(t);
      add(t, label + ' ' + mib(got) + ' of ' + mib(total));
    }

    async function download() {
      var built = st.built;
      var box = doc.getElementById('st-wrote-it');
      if (!built || !box.checked || st.busy) return;
      var dl = doc.getElementById('st-download');
      var err = doc.getElementById('st-download-error');
      clear(err);
      err.hidden = true;
      st.busy = true;
      dl.disabled = true;
      doc.getElementById('st-progress-box').hidden = false;
      var abort = typeof global.AbortController === 'function' ? new global.AbortController() : null;
      built.abort = abort;
      var signal = abort ? abort.signal : undefined;
      try {
        var base = await fetchImage(built.entry, function (got, total) { progress('Downloading the base image:', got, total); }, signal);
        if (st.built !== built) return;
        var out = await assemble(base, built.entry, built.region, function (got, total) { progress('Writing your settings into the image:', got, total); }, signal);
        base = null;
        if (st.built !== built) return;
        save(out, fileName(built.entry, built.site));
        var t = doc.getElementById('st-progress-text');
        clear(t);
        add(t, 'Done: ' + fileName(built.entry, built.site) + ', ' + mib(out.size) + '.');
        after(built.entry, built.site);
      } catch (e) {
        // a build the person voided says nothing; a refusal says whether a retry helps
        if (st.built !== built || (e && e.name === 'AbortError')) return;
        add(err, message(e));
        err.hidden = false;
      } finally {
        built.abort = null;
        st.busy = false;
        if (st.built === built) dl.disabled = !box.checked;
      }
    }

    function save(blob, name) {
      var url = URL.createObjectURL(blob);
      var a = el('a', { href: url, download: name, hidden: true });
      doc.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
    }

    // The steps to write the card (docs/operations.md, "Write the card"), and
    // where the image's parts come from.
    function after(e, site) {
      var name = fileName(e, site);
      var stem = e.file.replace(/\.img$/, '');
      var steps = [
        ['Write ', code(name), ' whole to a card at least ' + mib(e.size + 34 * MIB) + ': Raspberry Pi Imager (Choose OS ▸ Use custom), balenaEtcher, or ',
          code('gzip -dc ' + name + ' | sudo dd of=/dev/sdX bs=4M conv=fsync'), ' (check the device name with lsblk first). The rest of the card becomes the data partition.'],
        e.notes ? [e.title || e.board, ': ', e.notes] : null,
        ['Start the board. At the first boot the device takes in your settings, makes its data partition and starts the broker.'],
        ['While the broker has no user, the setup code makes its first admin on the gateway at https://<device address>:8445 (',
          el('a', { href: '../docs/operations.html#first-admin-from-a-setup-code-adr-0051-3' }, 'First admin from a setup code'),
          '). Studio does not ask for the code yet: that screen is planned.']
      ].filter(Boolean);
      fill('st-after', [
        el('h3', { style: 'margin: 0; font-size: 19px; font-weight: 600' }, 'Write the card'),
        el('ol', { style: 'margin: 0; padding-left: 22px; display: flex; flex-direction: column; gap: 10px; font-size: 15px; line-height: 1.6; color: #C5CBCE' },
          steps.map(function (s) { return el('li', null, s); })),
        el('div', { style: CARD + 'display: flex; flex-direction: column; gap: 8px; font-size: 14px; line-height: 1.6; color: #A3ABAF' }, [
          el('span', { style: 'font-size: 15px; font-weight: 600; color: #ECE9E1' }, 'What is in the image'),
          el('span', null, ['OpenWrt ' + e.openwrt + ': ', el('a', { href: 'https://github.com/openwrt/openwrt/tree/v' + encodeURIComponent(e.openwrt) }, 'its source')]),
          // the index names no commit of the broker's source, and no wyrmd-v* tag exists
          // yet: the releases of the repository are where its source is published
          el('span', null, ['wyrmd ' + e.wyrmd + ': ', el('a', { href: 'https://github.com/gencto/wyrm/releases' }, 'the WYRM releases')]),
          el('span', null, ['The packages of the image: ', el('a', { href: IMAGES + encodeURIComponent(stem + '.manifest') }, stem + '.manifest'),
            e.manifest_sha256 ? [' (SHA-256 ', code(e.manifest_sha256), ')'] : null]),
          el('span', null, ['More: ', el('a', { href: '../docs/operations.html#board-images-adr-0051-4' }, 'Board images'), ' in the operations guide.'])
        ])
      ]);
      doc.getElementById('st-after').hidden = false;
    }

    pruneCache(entries);
    return { state: st, choices: choices };
  }

  var api = {
    CONFIG_SIZE: CONFIG_SIZE,
    IMAGES: IMAGES,
    MSG: MSG,
    fetchImage: fetchImage,
    assemble: assemble,
    regionTransformer: regionTransformer,
    fileName: fileName,
    fieldOf: fieldOf,
    mount: mount
  };
  if (global.process) {
    global.wyrmStart = api;
    return;
  }

  // ----------------------------------------------------------- in a browser
  var doc = global.document;
  var script = doc.currentScript ? doc.currentScript.src : '';

  function status(kids, tone) {
    var n = doc.getElementById('start-status');
    if (!n) return;
    while (n.firstChild) n.removeChild(n.firstChild);
    (Array.isArray(kids) ? kids : [kids]).forEach(function (k) {
      n.appendChild(typeof k === 'string' ? doc.createTextNode(k) : k);
    });
    n.style.borderColor = tone === 'error' ? '#5A4330' : '#3A4249';
    n.hidden = false;
  }

  function none() {
    var guide = doc.getElementById('start-none');
    if (guide) guide.hidden = false;
    var s = doc.getElementById('start-status');
    if (s) s.hidden = true;
  }

  async function boot() {
    var res;
    try {
      res = await global.fetch(IMAGES + 'index.json', { cache: 'no-cache' });
    } catch (e) {
      status('The list of images could not be loaded. Check the connection and reload the page.', 'error');
      return;
    }
    if (res.status === 404) return none();
    if (!res.ok) {
      status('The list of images could not be loaded (HTTP ' + res.status + '). Reload the page.', 'error');
      return;
    }
    var text = await res.text();
    var wasm;
    try {
      wasm = await import(new URL('wasm/wyrm_image_web.js', script).href);
      await wasm.default();
    } catch (e) {
      status('This browser could not run the image builder (WebAssembly). Use a current Chrome, Edge, Firefox or Safari, or build the image with wyr image build.', 'error');
      return;
    }
    var entries;
    try {
      entries = wasm.check_index(text);
    } catch (e) {
      status('The list of images is refused: ' + message(e), 'error');
      return;
    }
    if (!entries.length) return none();
    var catalog = { links: [] };
    try {
      var c = await global.fetch(IMAGES + 'catalog.json', { cache: 'no-cache' });
      if (c.ok) catalog = await c.json();
    } catch (e) {
      // no links to choose then
    }
    var s = doc.getElementById('start-status');
    if (s) s.hidden = true;
    var steps = doc.getElementById('start-steps');
    if (steps) steps.hidden = false;
    mount(doc, wasm, entries, catalog);
  }

  boot();
})(globalThis);
