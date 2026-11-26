#!/usr/bin/env node
// Test of the install page's configurator (site/assets/install.js).
//
//     node tool/site/test_install.js [site/dist/install/index.html]
//
// It runs the real script against a small DOM stub, with the data of the
// built page, over every path × target × mode × set of links, and checks the
// files the page hands out:
//   - a `wyrmd.json5` with a link in process mode, or with a process package
//     among its links, has a `tls/` listener: `wyrmd` refuses to start without
//     one (docs/links.md); a link in external mode needs one too;
//   - no config sets `insecure_plaintext`;
//   - every key of a config is in the list below, and every top-level key is
//     a field of the broker's config (crates/wyrmd/src/lib.rs);
//   - a path that is still planned shows its steps as comments only, and the
//     page opens on a path that works today.
// Node 18+, no dependencies.
'use strict';

const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.argv[2] || path.join(REPO, 'site/dist/install/index.html'));
const SCRIPT = path.join(REPO, 'site/assets/install.js');

// The keys the page may write, as paths; `links.*` is one link.
const ALLOWED = new Set([
  'site', 'data_dir', 'listen', 'tls_names',
  'gateway', 'gateway.listen', 'gateway.admin_user', 'gateway.tls', 'gateway.setup_file',
  'packages', 'packages.repository', 'packages.seed_dir',
  'scheduler', 'scheduler.enabled', 'dql', 'dql.enabled',
  'alarm', 'alarm.enabled', 'uplink', 'uplink.enabled',
  'links', 'links.*', 'links.*.driver', 'links.*.mode',
]);

// ------------------------------------------------------------------ DOM stub
function node(tag) {
  const n = {
    tag, children: [], attrs: {}, style: { cssText: '' }, value: '', listeners: {},
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; },
    removeAttribute(k) { delete this.attrs[k]; },
    addEventListener(k, f) { (this.listeners[k] = this.listeners[k] || []).push(f); },
    appendChild(c) { this.children.push(c); return c; },
    removeChild(c) { this.children.splice(this.children.indexOf(c), 1); return c; },
    focus() {},
    get firstChild() { return this.children[0] || null; },
    get textContent() {
      return this.text !== undefined ? this.text : this.children.map((c) => c.textContent).join('');
    },
  };
  return n;
}

function pageData() {
  if (!fs.existsSync(PAGE)) {
    throw new Error(`${PAGE} is missing: run python3 tool/site/build.py first`);
  }
  const html = fs.readFileSync(PAGE, 'utf8');
  const m = html.match(/<script type="application\/json" id="install-data">([\s\S]*?)<\/script>/);
  if (!m) throw new Error(`${PAGE}: no #install-data`);
  JSON.parse(m[1]);
  return m[1];
}

function load() {
  const byId = {};
  const data = node('script');
  data.text = pageData();
  byId['install-data'] = data;
  const input = node('input');
  input.value = 'plant';
  byId['site-name'] = input;
  const document = {
    activeElement: null,
    getElementById(id) { return byId[id] || (byId[id] = node('div')); },
    querySelector() { return null; },
    createElement: node,
    createElementNS(ns, tag) { return node(tag); },
    createTextNode(t) { const n = node('#text'); n.text = String(t); return n; },
  };
  let api = null;
  const window = { wyrmInstallTest(a) { api = a; } };
  new Function('window', 'document', fs.readFileSync(SCRIPT, 'utf8'))(window, document);
  if (!api) throw new Error('install.js did not call the test hook');
  return api;
}

// ------------------------------------------------------------- json5 subset
// What the page writes: `//` comments, bare keys, trailing commas.
function parseConfig(text) {
  const json = text
    .split('\n').map((l) => l.replace(/(^|\s)\/\/.*$/, '$1')).join('\n')
    .replace(/([{,]\s*)([A-Za-z_][A-Za-z0-9_-]*)\s*:/g, '$1"$2":')
    .replace(/,(\s*[}\]])/g, '$1');
  return JSON.parse(json);
}

function keyPaths(value, prefix, out) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return out;
  for (const k of Object.keys(value)) {
    const p = prefix === 'links' ? 'links.*' : prefix ? `${prefix}.${k}` : k;
    out.add(p);
    keyPaths(value[k], p, out);
  }
  return out;
}

// --------------------------------------------------------------------- run
const api = load();
const configRs = fs.readFileSync(path.join(REPO, 'crates/wyrmd/src/lib.rs'), 'utf8');
const official = JSON.parse(fs.readFileSync(path.join(REPO, 'links/official.json'), 'utf8'));
const builtin = new Set(official.links.map((l) => (l.forms || {}).builtin).filter(Boolean));
const errors = [];
let count = 0;
let withProcess = 0;

const first = api.PATHS.find((p) => p.id === api.state.path);
if (!first || first.st === 'planned') {
  errors.push(`the page opens on "${api.state.path}", a path that is planned`);
}

const sets = api.PRESETS.map((p) => ({ name: p.id, preset: p.id, picked: null }));
sets.push({ name: 'every link', preset: 'broker', picked: api.LINKS.map((l) => l.id) });
for (const l of api.LINKS) sets.push({ name: `only ${l.id}`, preset: 'broker', picked: [l.id] });

for (const p of api.PATHS) {
  for (const t of api.TARGETS[p.id].filter((x) => !x.off)) {
    for (const mode of ['inside', 'separate']) {
      for (const set of sets) {
        const where = `${p.id} / ${t.id} / ${mode} / ${set.name}`;
        Object.assign(api.state, { path: p.id, target: t.id, mode, preset: set.preset, picked: set.picked, site: 'plant' });
        let m;
        try {
          api.render();
          m = api.model();
        } catch (e) {
          errors.push(`${where}: ${e.stack || e}`);
          continue;
        }
        count += 1;
        let cfg;
        try {
          cfg = parseConfig(m.config);
        } catch (e) {
          errors.push(`${where}: wyrmd.json5 does not parse: ${e.message}\n${m.config}`);
          continue;
        }
        if (/insecure_plaintext/.test(m.config)) errors.push(`${where}: sets insecure_plaintext`);
        for (const k of keyPaths(cfg, '', new Set())) {
          if (!ALLOWED.has(k)) errors.push(`${where}: key ${k} is not in the list of the test`);
        }
        for (const k of Object.keys(cfg)) {
          if (!new RegExp(`^\\s*pub ${k}:`, 'm').test(configRs)) {
            errors.push(`${where}: key ${k} is not a field of the broker's config`);
          }
        }
        const links = cfg.links || {};
        const modes = Object.values(links).map((l) => l.mode).filter(Boolean);
        for (const [id, l] of Object.entries(links)) {
          if (!builtin.has(l.driver)) errors.push(`${where}: link ${id}: driver ${l.driver} is not built in`);
          if (l.mode && !['process', 'external'].includes(l.mode)) errors.push(`${where}: link ${id}: mode ${l.mode}`);
        }
        const processPackage = m.pkgs.some((l) => l.f.k === 'pkgproc');
        const needsTls = modes.length > 0 || processPackage;
        const hasTls = (cfg.listen || []).some((e) => e.startsWith('tls/'));
        if (modes.includes('process') || processPackage) withProcess += 1;
        if (needsTls && !hasTls) {
          errors.push(`${where}: a link runs as a process or outside the broker, and listen has no tls/: ${JSON.stringify(cfg.listen)}`);
        }
        for (const e of cfg.listen || []) {
          if (e.startsWith('tcp/') && !e.startsWith('tcp/127.0.0.1:')) errors.push(`${where}: plaintext listener ${e} is not on loopback`);
        }
        if (p.st === 'planned') {
          const live = m.commands.split('\n').filter((l) => l.trim() && !l.startsWith('#'));
          if (live.length) errors.push(`${where}: a planned path shows a command to run: ${live[0]}`);
        }
        if (p.id === 'docker' && !m.compose) errors.push(`${where}: no compose.yaml`);
      }
    }
  }
}

if (withProcess === 0) errors.push('no combination had a process link: the test checks nothing');
for (const e of errors.slice(0, 40)) console.error(`install: ${e}`);
if (errors.length) {
  console.error(`install: ${errors.length} error(s) in ${count} combinations`);
  process.exit(1);
}
console.log(`install: ${count} combinations checked, ${withProcess} with a link process; all configs are good`);
