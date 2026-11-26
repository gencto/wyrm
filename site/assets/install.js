// The install page's configurator (site/install/index.html).
//
// It reads the official links and the files of the links release from the
// JSON that tool/site/build.py puts into the page (`#install-data`), and
// renders the path cards, the link picker and the files for the choice:
// `wyrmd.json5`, `compose.yaml` and the commands. Nothing leaves the browser.
// No dependencies. Every text goes into the page as a text node, so the site
// name a person types is never read as HTML.
(function () {
  'use strict';

  var dataEl = document.getElementById('install-data');
  if (!dataEl) return;
  var DATA;
  try {
    DATA = JSON.parse(dataEl.textContent);
  } catch (e) {
    return;
  }

  var ACCENT = '#E8893A';
  var V = DATA.version;
  var REL = DATA.release;
  var ASSETS = REL.assets || {};
  var MIB = 1024 * 1024;

  // Links that every `wyrmd` carries as an embedded service, switched by
  // `<id>: { enabled }` in wyrmd.json5 (crates/wyrmd: SchedulerSection,
  // DqlSection, AlarmSection, UplinkSection).
  var SERVICES = ['scheduler', 'dql', 'alarm', 'uplink'];
  // Compressed size of the `wyrm/wyrmd` image and of one link image, MiB,
  // measured for linux/arm64 (deploy/docker/README.md, "Measured").
  var BROKER_MIB = 26.6;
  var LINK_IMAGE_MIB = 6.7;
  var CATEGORIES = ['Equipment', 'File stores', 'History sync', 'Apps', 'Messaging', 'Test'];

  var PATHS = [
    { id: 'image', t: 'USB or SD image', s: 'Flash a board. It boots straight into wyrmd.', st: 'planned' },
    { id: 'archive', t: 'Archive for an OS', s: 'One binary for Linux or macOS: unpack, set a password, run.', st: 'planned' },
    { id: 'docker', t: 'Docker', s: 'A compose file: the broker and its links as small scratch images.', st: 'source' },
    { id: 'source', t: 'From source', s: 'cargo build on a Linux or macOS machine with Rust.', st: 'available' }
  ];
  // `rel`: the target name of a broker archive, `<arch>-<os>[-musl]`
  // (packaging/wyrmd/README.md). `host`: the host name of a link package.
  var TARGETS = {
    image: [
      { id: 'rpi4', t: 'Raspberry Pi 4', s: 'arm64, SD card', host: 'linux-aarch64' },
      { id: 'rpi5', t: 'Raspberry Pi 5', s: 'arm64, SD card', host: 'linux-aarch64' },
      { id: 'bpi-r4', t: 'Banana Pi BPI-R4', s: 'arm64, SD card to eMMC', host: 'linux-aarch64' }
    ],
    archive: [
      { id: 'lx64', t: 'Linux', s: 'x86-64, static', host: 'linux-x86_64', rel: 'x86_64-linux-musl' },
      { id: 'la64', t: 'Linux', s: 'ARM64, static', host: 'linux-aarch64', rel: 'aarch64-linux-musl' },
      { id: 'mac', t: 'macOS', s: 'Apple silicon', host: 'macos-aarch64', rel: 'aarch64-macos' },
      { id: 'win', t: 'Windows', s: 'not built yet', off: true }
    ],
    docker: [
      { id: 'amd64', t: 'linux/amd64', s: 'x86-64 hosts', host: 'linux-x86_64' },
      { id: 'arm64', t: 'linux/arm64', s: 'ARM boards, Apple silicon', host: 'linux-aarch64' }
    ],
    source: [{ id: 'any', t: 'This machine', s: 'Linux or macOS with Rust 1.97+', host: null }]
  };
  var PRESETS = [
    { id: 'broker', t: 'Broker only', ids: [] },
    { id: 'plant', t: 'Plant floor', ids: ['modbus', 'opcua', 's7', 'mqtt', 'alarm', 'postgres'] },
    { id: 'building', t: 'Building', ids: ['bacnet', 'modbus', 'snmp', 'scheduler', 'alarm', 'telegram'] },
    { id: 'hub', t: 'Data hub', ids: ['uplink', 'influxdb', 'dql', 's3'] }
  ];
  var STATUS = {
    available: { t: 'Available', c: '#6CC4B0', b: '#2F5A51' },
    source: { t: 'From source today', c: ACCENT, b: '#5A4330' },
    planned: { t: 'Planned', c: '#A3ABAF', b: '#3A4249' }
  };
  var ICONS = {
    image: [['rect', { x: 6, y: 9, width: 12, height: 13, rx: 2 }], ['path', { d: 'M9 9V3h6v6' }], ['path', { d: 'M10 5h1M13 5h1' }]],
    archive: [['rect', { x: 3, y: 4, width: 18, height: 5, rx: 1 }], ['path', { d: 'M5 9v10a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V9' }], ['path', { d: 'M10 13h4' }]],
    docker: [['rect', { x: 3, y: 11, width: 18, height: 8, rx: 1.5 }], ['rect', { x: 5, y: 7, width: 4, height: 4 }], ['rect', { x: 10, y: 7, width: 4, height: 4 }], ['rect', { x: 10, y: 3, width: 4, height: 4 }], ['rect', { x: 15, y: 7, width: 4, height: 4 }]],
    source: [['polyline', { points: '16 18 22 12 16 6' }], ['polyline', { points: '8 6 2 12 8 18' }]]
  };

  // One official link as the page needs it.
  var LINKS = (DATA.links || []).map(function (l) {
    var forms = l.forms || {};
    return {
      id: l.id, t: l.title || l.id, s: l.summary || '', c: l.category || '', v: l.version || V,
      svc: SERVICES.indexOf(l.id) >= 0,
      driver: forms.builtin || null,
      wasm: forms.wasm || null,
      process: forms.process || null,
      // `wyrm/link-<id>` is built from the crate `wyrm-link-<id>` (deploy/docker/Dockerfile)
      container: !!forms.builtin && !!forms.process && l.crate === 'wyrm-link-' + l.id
    };
  });
  var known = {};
  LINKS.forEach(function (l) { known[l.id] = true; });
  PRESETS.forEach(function (p) { p.ids = p.ids.filter(function (id) { return known[id]; }); });

  // The page opens on a path that works today.
  var state = { path: 'source', target: 'any', preset: 'plant', picked: null, mode: 'inside', site: 'plant' };

  // ------------------------------------------------------------------- DOM
  var SVG = 'http://www.w3.org/2000/svg';

  function el(tag, attrs, kids) {
    var n = document.createElement(tag);
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
      n.appendChild(typeof c === 'object' ? c : document.createTextNode(String(c)));
    });
  }
  function fill(id, kids) {
    var n = document.getElementById(id);
    if (!n) return null;
    while (n.firstChild) n.removeChild(n.firstChild);
    add(n, kids);
    return n;
  }
  function icon(name) {
    var s = document.createElementNS(SVG, 'svg');
    var a = { width: 28, height: 28, viewBox: '0 0 24 24', fill: 'none', stroke: ACCENT, 'stroke-width': 1.8, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true' };
    for (var k in a) s.setAttribute(k, a[k]);
    ICONS[name].forEach(function (p) {
      var c = document.createElementNS(SVG, p[0]);
      for (var k2 in p[1]) c.setAttribute(k2, p[1][k2]);
      s.appendChild(c);
    });
    return s;
  }
  function code(text) { return el('code', null, text); }

  var MONO = "font-family: 'IBM Plex Mono', monospace; ";
  var PRE = 'margin: 0; padding: 18px 20px; border-radius: 12px; background: #161A1D; border: 1px solid #252B30; font-size: 13px; color: #C5CBCE; white-space: pre; ';

  function mib(n) { return (Math.round(n * 10) / 10).toFixed(1) + ' MiB'; }
  function plural(n, word) { return n + ' ' + word + (n === 1 ? '' : 's'); }

  // The steps of a path that is still planned: every line is a comment, so
  // nothing in the box can be pasted and run against a file that is not there.
  function planned(head, lines) {
    return ['# ' + head].concat(lines.map(function (l) { return l ? '#   ' + l : '#'; })).join('\n');
  }

  // ------------------------------------------------------------------ model
  function model() {
    var st = state;
    var path = st.path;
    var targets = TARGETS[path];
    var tgt = targets.filter(function (t) { return t.id === st.target && !t.off; })[0] ||
      targets.filter(function (t) { return !t.off; })[0];
    var host = tgt.host;
    var preset = PRESETS.filter(function (p) { return p.id === st.preset; })[0];
    var picked = st.picked || (preset ? preset.ids : []);
    var isSel = function (id) { return picked.indexOf(id) >= 0; };
    var sep = st.mode === 'separate';
    var siteOk = /^[a-z][a-z0-9-]{0,30}$/.test(st.site);
    var site = siteOk ? st.site : 'plant';
    var docker = path === 'docker';
    var image = path === 'image';

    // The release file of a link's package in one form, if the release has it.
    var asset = function (l, kind) {
      var name = kind === 'wasm'
        ? (l.wasm ? l.wasm + '-' + l.v + '.zip' : null)
        : (l.process && host ? l.process + '-' + l.v + '-' + host + '.zip' : null);
      if (!name || !(name in ASSETS)) return null;
      return { name: name, mb: ASSETS[name] / MIB };
    };
    // How each link runs on this path.
    var form = function (l) {
      if (l.svc || (l.driver && !l.process && !l.wasm)) return { k: 'builtin', t: 'built in', mb: 0 };
      if (l.driver) {
        if (!sep) return { k: 'builtin', t: 'built in', mb: 0 };
        if (docker && l.container) return { k: 'container', t: 'own container', mb: LINK_IMAGE_MIB, about: true };
        if (docker) return { k: 'builtin', t: 'built in', mb: 0 };
        return { k: 'process', t: 'process', mb: 0 };
      }
      var w = asset(l, 'wasm');
      var p = asset(l, 'process');
      // an image carries the package-only links as WASM (ADR 0051 §1)
      if (!sep || image || docker || !host || !l.process) {
        return { k: 'wasm', t: sep && docker ? 'WASM in the broker' : 'WASM', mb: w ? w.mb : 0, file: w };
      }
      return { k: 'pkgproc', t: 'process', mb: p ? p.mb : 0, file: p };
    };
    var sel = LINKS.filter(function (l) { return isSel(l.id); }).map(function (l) {
      var c = {};
      for (var k in l) c[k] = l[k];
      c.f = form(l);
      return c;
    });
    var pkgs = sel.filter(function (l) { return l.f.k === 'wasm' || l.f.k === 'pkgproc'; });
    var conts = sel.filter(function (l) { return l.f.k === 'container'; });
    var drivers = sel.filter(function (l) { return l.driver && !l.svc; });

    // ---- wyrmd.json5
    var C = [];
    C.push('// wyrmd.json5 · site ' + site + ' · made on the WYRM install page');
    C.push('{');
    C.push('  site: "' + site + '",');
    C.push('  data_dir: "' + (image ? '/srv/wyrm' : docker ? '/data' : './data') + '",');
    // A link in process mode, built in or from a process package, dials the
    // broker over TLS: `wyrmd` refuses to start one without a `tls/` listener
    // (docs/links.md, "Process mode needs a tls/ listener").
    var procs = sel.some(function (l) { return l.f.k === 'process' || l.f.k === 'pkgproc'; });
    if (conts.length) {
      C.push('  // plaintext on loopback only; the link containers dial TLS');
      C.push('  listen: ["tcp/127.0.0.1:7447", "tls/0.0.0.0:7448"],');
      C.push('  tls_names: ["wyrmd", "localhost", "127.0.0.1"],');
    } else if (procs) {
      C.push('  // the link processes dial TLS on loopback, with certificates from the site CA');
      C.push('  listen: ["tcp/127.0.0.1:7447", "tls/127.0.0.1:7448"],');
    } else {
      C.push('  listen: ["tcp/127.0.0.1:7447"],');
    }
    if (image) {
      C.push('  // the certificate comes from the site CA; the first admin from the setup code');
      C.push('  gateway: { listen: "0.0.0.0:8445", tls: "site_ca", setup_file: "/etc/wyrm/setup", admin_user: "admin" },');
    } else {
      C.push('  // Studio on another machine: listen there with tls: "site_ca", or tls_cert and tls_key');
      C.push('  gateway: { listen: "127.0.0.1:8445", admin_user: "admin" },');
    }
    C.push('  // Install Link ▸ from Repository reads the official links release');
    C.push('  packages: { repository: "official"' + (image && pkgs.length ? ', seed_dir: "/usr/share/wyrm/seed"' : '') + ' },');
    LINKS.filter(function (l) { return l.svc; }).forEach(function (l) {
      C.push('  ' + l.id + ': { enabled: ' + isSel(l.id) + ' },');
    });
    if (drivers.length) {
      C.push('  links: {');
      drivers.forEach(function (l) {
        var mode = l.f.k === 'container' ? ', mode: "external"' : l.f.k === 'process' ? ', mode: "process"' : '';
        var hint = l.id === 'agent' ? '// its LLM key: Studio ▸ Links ▸ agent ▸ Edit' : '// add connections in Studio';
        C.push('    ' + l.id + ': { driver: "' + l.driver + '"' + mode + ' },  ' + hint);
      });
      C.push('  },');
    } else {
      C.push('  links: {},');
    }
    if (pkgs.length) {
      var where = image
        ? 'carried by the image, installed on the first start'
        : 'install from Studio ▸ Links ▸ Install Link ▸ from Repository';
      C.push('  // Packages, ' + where + ':');
      pkgs.forEach(function (l) { C.push('  //   ' + l.id + ' ' + l.v + ' (' + (l.f.k === 'wasm' ? 'WASM' : 'process') + ')'); });
    }
    C.push('}');

    // ---- compose.yaml
    var Y = [];
    if (docker) {
      var links = conts.map(function (l) { return l.id; }).join(' ');
      var plat = 'linux/' + (tgt.id === 'arm64' ? 'arm64' : 'amd64');
      Y.push('# compose.yaml · site ' + site + ' · ' + plat);
      Y.push('# In a clone of github.com/gencto/wyrm, beside wyrmd.json5:');
      Y.push("#   export WYRM_GATEWAY_ADMIN_PASSWORD='<a password>'");
      Y.push('#   docker compose up -d --build');
      Y.push('# The gateway listens on the broker\'s loopback: use the tools service, or see');
      Y.push('# deploy/docker/README.md for Studio on this host.');
      Y.push('x-hardened: &hardened');
      Y.push('  read_only: true');
      Y.push('  cap_drop: [ALL]');
      Y.push('  security_opt: ["no-new-privileges:true"]');
      Y.push('  tmpfs: ["/tmp"]');
      Y.push('x-build: &build');
      Y.push('  context: .');
      Y.push('  dockerfile: deploy/docker/Dockerfile');
      Y.push('  args: { LINKS: "' + links + '", SIMS: "" }');
      if (conts.length) {
        Y.push('x-link-env: &link-env');
        Y.push('  WYRM_SITE: ' + site);
        Y.push('  WYRM_ENDPOINT: tls/wyrmd:7448');
        Y.push('  WYRM_CA: /link/ca.pem');
        Y.push('  WYRM_CERT: /link/link.pem');
        Y.push('  WYRM_KEY: /link/link.key');
        Y.push('  WYRM_TOKEN_FILE: /link/token');
      }
      Y.push('');
      Y.push('services:');
      Y.push('  wyrmd:');
      Y.push('    <<: *hardened');
      Y.push('    image: wyrm/wyrmd:local');
      Y.push('    build: { <<: *build, target: wyrmd }');
      Y.push('    platform: ' + plat);
      Y.push('    environment:');
      Y.push('      WYRM_GATEWAY_ADMIN_PASSWORD: ${WYRM_GATEWAY_ADMIN_PASSWORD:?set the gateway admin password}');
      Y.push('    volumes:');
      Y.push('      - wyrm-data:/data');
      Y.push('      - ./wyrmd.json5:/etc/wyrm/wyrmd.json5:ro');
      Y.push('    restart: unless-stopped');
      if (conts.length) {
        Y.push('');
        Y.push('  # hands each link only its own certificate, key and token');
        Y.push('  provision:');
        Y.push('    image: alpine:3.22');
        Y.push('    volumes: [wyrm-data:/wyrm:ro, link-files:/out]');
        Y.push('    environment: { LINKS: "' + links + '" }');
        Y.push('    command:');
        Y.push('      - sh');
        Y.push('      - -euc');
        Y.push('      - |');
        Y.push('        for id in $$LINKS; do');
        Y.push('          d=/wyrm/links/$$id');
        Y.push('          for i in $$(seq 120); do');
        Y.push('            [ -s /wyrm/pki/ca.pem ] && [ -s $$d/token ] && [ -s $$d/link.key ] && break');
        Y.push('            sleep 1');
        Y.push('          done');
        Y.push('          mkdir -p /out/$$id');
        Y.push('          cp /wyrm/pki/ca.pem $$d/link.pem $$d/link.key $$d/token /out/$$id/');
        Y.push('          chown -R 65532:65532 /out/$$id');
        Y.push('          chmod 0400 /out/$$id/link.key /out/$$id/token');
        Y.push('        done');
        Y.push('    depends_on: [wyrmd]');
        Y.push('    network_mode: none');
        conts.forEach(function (l) {
          Y.push('');
          Y.push('  link-' + l.id + ':');
          Y.push('    <<: *hardened');
          Y.push('    image: wyrm/link-' + l.id + ':local');
          Y.push('    build: { <<: *build, target: link, args: { LINKS: "' + links + '", SIMS: "", LINK: ' + l.id + ' } }');
          Y.push('    platform: ' + plat);
          Y.push('    environment: { <<: *link-env, WYRM_LINK_ID: ' + l.id + ' }');
          Y.push('    volumes:');
          Y.push('      - { type: volume, source: link-files, target: /link, read_only: true, volume: { subpath: ' + l.id + ' } }');
          Y.push('      - ' + l.id + '-state:/state');
          Y.push('    depends_on:');
          Y.push('      provision: { condition: service_completed_successfully }');
          Y.push('    restart: unless-stopped');
        });
      }
      Y.push('');
      Y.push('  # wyr and wyrm-agent beside the gateway: docker compose run --rm tools');
      Y.push('  tools:');
      Y.push('    image: wyrm/tools:local');
      Y.push('    build: { <<: *build, target: tools }');
      Y.push('    network_mode: service:wyrmd');
      Y.push('    environment:');
      Y.push('      WYR_GATEWAY_PASSWORD: ${WYRM_GATEWAY_ADMIN_PASSWORD:?set the gateway admin password}');
      Y.push('    profiles: [tools]');
      Y.push('    stdin_open: true');
      Y.push('    tty: true');
      Y.push('');
      Y.push('volumes:');
      Y.push('  wyrm-data:');
      if (conts.length) {
        Y.push('  link-files:');
        conts.forEach(function (l) { Y.push('  ' + l.id + '-state:'); });
      }
    }

    // ---- file name, commands, note
    var linksMb = sel.reduce(function (a, l) { return a + (l.f.mb || 0); }, 0);
    var file = '', commands = '', note = '', status = '';
    if (image) {
      file = 'wyrm-' + V + '-' + tgt.id + '.img.gz';
      commands = planned('No image is published yet. When one is, you will flash it like this:', [
        'Raspberry Pi Imager: Choose OS ▸ Use custom ▸ ' + file,
        'balenaEtcher: Flash from file ▸ ' + file,
        'or from a shell (replace sdX with your card; check it with lsblk first):',
        'gzip -dc ' + file + ' | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress'
      ]);
      note = 'Planned. No image is published yet: this panel shows the flow the image builder will run. The file name is not final.';
      status = 'planned';
    } else if (path === 'archive') {
      file = 'wyrmd-' + V + '-' + tgt.rel + '.tar.gz';
      var base = 'https://github.com/gencto/wyrm/releases/download/wyrmd-v' + V + '/';
      commands = planned('No wyrmd-v* release is published yet: these addresses do not exist today.\n# When a release is out, the steps will be:', [
        '1. Download the broker and its signed release document',
        'curl -fLO ' + base + file,
        'curl -fLO ' + base + 'wyrmd-' + V + '.release.json',
        'compare with the sha256 of this file in the document:',
        (tgt.id === 'mac' ? 'shasum -a 256 ' : 'sha256sum ') + file,
        '',
        '2. Unpack and start, beside wyrmd.json5 from this page',
        'tar xzf ' + file,
        "export WYRM_GATEWAY_ADMIN_PASSWORD='<a password>'",
        './wyrmd -c wyrmd.json5'
      ]);
      note = 'Planned for the broker: no wyrmd-v* release is published yet.' +
        (pkgs.some(function (l) { return l.f.file; }) ? ' The link files are published today: their direct links below work now.' : '');
      status = 'planned';
    } else if (docker) {
      file = 'compose.yaml + wyrmd.json5';
      commands = [
        'git clone https://github.com/gencto/wyrm && cd wyrm',
        '# save compose.yaml and wyrmd.json5 from this page here',
        "export WYRM_GATEWAY_ADMIN_PASSWORD='<a password>'",
        'docker compose up -d --build',
        'docker compose run --rm tools      # wyr and wyrm-agent'
      ].join('\n');
      note = 'Works today: the images are built from the repository. A cold build of the broker and every link takes about 90 min on 2 jobs (Apple M4 Max); this file builds only the links you picked. Published images are planned.';
      status = 'source';
    } else {
      file = 'wyrmd.json5';
      commands = [
        'git clone https://github.com/gencto/wyrm && cd wyrm',
        'cargo build --release -p wyrmd -p wyr',
        '# save wyrmd.json5 from this page here',
        "export WYRM_GATEWAY_ADMIN_PASSWORD='<a password>'",
        'target/release/wyrmd -c wyrmd.json5'
      ].join('\n');
      note = 'Works today on Linux and macOS. Links that are packages install from Studio once the broker runs.';
      status = 'available';
    }
    var sizeRows = [];
    if (path !== 'source') {
      sizeRows.push({ k: docker ? 'wyrm/wyrmd image' : 'wyrmd', v: '≈ ' + mib(BROKER_MIB) });
      if (docker) sizeRows.push({ k: plural(conts.length, 'link image'), v: (conts.length ? '≈ ' : '') + mib(conts.length * LINK_IMAGE_MIB) });
      var pk = pkgs.reduce(function (a, l) { return a + l.f.mb; }, 0);
      sizeRows.push({ k: plural(pkgs.length, 'package') + (docker ? ', from the repository' : ''), v: mib(pk) });
      if (image) sizeRows.push({ k: 'base system for the board', v: '[at release]' });
      sizeRows.push({ k: 'WYRM in all', v: '≈ ' + mib(BROKER_MIB + linksMb) });
    }

    var today = pkgs.filter(function (l) { return l.f.file; }).map(function (l) {
      return { name: l.f.file.name, url: REL.download + l.f.file.name, size: mib(l.f.file.mb) };
    });
    var summary = sel.length
      ? sel.map(function (l) { return l.t + ' · ' + l.f.t; }).join(', ')
      : 'No links: the broker with its historian, storage, flows and gateway.';
    var imgSteps = [
      { n: '1', t: 'Base system', s: 'The release image for ' + tgt.t + ', fetched once and checked by SHA-256' },
      { n: '2', t: 'Your broker', s: 'wyrmd.json5 for site ' + site + ', written into the image' },
      { n: '3', t: 'Your links', s: pkgs.length ? plural(pkgs.length, 'package') + ' of those the base image carries' : 'Built-in drivers only' },
      { n: '4', t: 'Download', s: file + ', with a one-time setup code for the first admin' }
    ];
    return {
      path: path, tgt: tgt, targets: targets, host: host, picked: picked, isSel: isSel, sep: sep, docker: docker, image: image,
      siteOk: siteOk, site: site, form: form, sel: sel, pkgs: pkgs, config: C.join('\n'), compose: Y.join('\n'),
      commands: commands, file: file, note: note, status: STATUS[status], sizeRows: sizeRows, today: today,
      summary: summary, imgSteps: imgSteps
    };
  }

  // ------------------------------------------------------------------- view
  function set(change) {
    for (var k in change) state[k] = change[k];
    var a = document.activeElement;
    var key = a && a.getAttribute ? a.getAttribute('data-key') : null;
    render();
    if (key) {
      var again = document.querySelector('[data-key="' + key + '"]');
      if (again) again.focus();
    }
  }
  function firstTarget(path) {
    return TARGETS[path].filter(function (t) { return !t.off; })[0].id;
  }

  function render() {
    var m = model();

    fill('cfg-paths', PATHS.map(function (p) {
      var on = p.id === m.path;
      var sc = STATUS[p.st];
      return el('button', {
        type: 'button', 'aria-pressed': on ? 'true' : 'false', 'data-key': 'path-' + p.id,
        style: 'text-align: left; min-height: 168px; padding: 20px; border-radius: 12px; border: 1px solid ' + (on ? ACCENT : '#2A3136') + '; background: ' + (on ? '#1B2025' : '#161A1D') + '; color: #ECE9E1; display: flex; flex-direction: column; gap: 10px',
        onclick: function () { set({ path: p.id, target: firstTarget(p.id) }); }
      }, [
        icon(p.id),
        el('span', { style: 'font-size: 18px; font-weight: 600' }, p.t),
        el('span', { style: 'font-size: 14px; line-height: 1.5; color: #A3ABAF' }, p.s),
        el('span', { style: 'margin-top: auto; align-self: flex-start; padding: 3px 10px; border-radius: 999px; border: 1px solid ' + sc.b + '; ' + MONO + 'font-size: 12px; color: ' + sc.c }, sc.t)
      ]);
    }));

    fill('cfg-targets', m.targets.map(function (t) {
      var on = t.id === m.tgt.id;
      return el('button', {
        type: 'button', 'aria-pressed': on ? 'true' : 'false', disabled: !!t.off, 'data-key': 'target-' + t.id,
        style: 'min-height: 44px; padding: 8px 16px; border-radius: 10px; border: 1px solid ' + (on ? ACCENT : '#2A3136') + '; background: ' + (on ? '#1B2025' : 'transparent') + '; color: ' + (t.off ? '#7D868B' : '#ECE9E1') + '; display: flex; flex-direction: column; align-items: flex-start; gap: 2px; text-align: left' + (t.off ? '; cursor: not-allowed' : ''),
        onclick: function () { if (!t.off) set({ target: t.id }); }
      }, [
        el('span', { style: 'font-size: 14px; font-weight: 600' }, t.t),
        el('span', { style: MONO + 'font-size: 12px; color: #8E979C' }, t.s)
      ]);
    }));

    fill('cfg-presets', PRESETS.concat([{ id: 'custom', t: 'Custom' }]).map(function (p) {
      var on = state.picked ? p.id === 'custom' : p.id === state.preset;
      return el('button', {
        type: 'button', 'aria-pressed': on ? 'true' : 'false', 'data-key': 'preset-' + p.id,
        style: 'min-height: 44px; padding: 8px 18px; border-radius: 999px; border: 1px solid ' + (on ? ACCENT : '#2A3136') + '; background: ' + (on ? '#1B2025' : 'transparent') + '; color: #ECE9E1; font-size: 14px; font-weight: 500',
        onclick: function () {
          if (p.id === 'custom') set({ picked: m.picked.slice() });
          else set({ preset: p.id, picked: null });
        }
      }, p.t);
    }));

    var modes = [
      { id: 'inside', t: 'Inside the broker', s: 'Built-in drivers and WASM: one process, the smallest footprint' },
      { id: 'separate', t: 'Separate processes', s: m.docker ? 'Equipment and file links in their own containers' : 'Each link supervised by the broker, restarted on its own' }
    ];
    fill('cfg-modes', modes.map(function (md) {
      var on = md.id === state.mode;
      return el('button', {
        type: 'button', 'aria-pressed': on ? 'true' : 'false', 'data-key': 'mode-' + md.id,
        style: 'text-align: left; min-height: 64px; padding: 14px 18px; border-radius: 10px; border: 1px solid ' + (on ? ACCENT : '#2A3136') + '; background: ' + (on ? '#1B2025' : 'transparent') + '; color: #ECE9E1; display: flex; flex-direction: column; gap: 4px',
        onclick: function () { set({ mode: md.id }); }
      }, [
        el('span', { style: 'font-size: 15px; font-weight: 600' }, md.t),
        el('span', { style: 'font-size: 13px; line-height: 1.5; color: #A3ABAF' }, md.s)
      ]);
    }));

    var cats = CATEGORIES.slice();
    LINKS.forEach(function (l) { if (cats.indexOf(l.c) < 0) cats.push(l.c); });
    fill('cfg-groups', cats.map(function (c) {
      var items = LINKS.filter(function (l) { return l.c === c; });
      if (!items.length) return null;
      return el('div', { role: 'group', 'aria-label': c, style: 'display: flex; flex-direction: column; gap: 10px' }, [
        el('span', { style: MONO + 'font-size: 13px; letter-spacing: 0.06em; text-transform: uppercase; color: #8E979C' }, c),
        el('div', { style: 'display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 10px' }, items.map(function (l) {
          var on = m.isSel(l.id);
          var f = m.form(l);
          var size = f.mb ? (f.about ? '≈ ' : '') + mib(f.mb)
            : (f.k === 'builtin' || f.k === 'process' ? '0 MiB extra' : 'from the release');
          return el('button', {
            type: 'button', 'aria-pressed': on ? 'true' : 'false', 'data-key': 'link-' + l.id,
            style: 'text-align: left; min-height: 76px; padding: 12px 14px; border-radius: 10px; border: 1px solid ' + (on ? ACCENT : '#2A3136') + '; background: ' + (on ? '#1B2025' : '#161A1D') + '; color: #ECE9E1; display: flex; gap: 12px; align-items: flex-start',
            onclick: function () {
              var cur = m.picked.slice();
              var i = cur.indexOf(l.id);
              if (i >= 0) cur.splice(i, 1); else cur.push(l.id);
              set({ picked: cur });
            }
          }, [
            el('span', { 'aria-hidden': 'true', style: 'flex: 0 0 auto; width: 16px; height: 16px; margin-top: 3px; border-radius: 4px; border: 1.5px solid ' + (on ? ACCENT : '#4A535A') + '; background: ' + (on ? ACCENT : 'transparent') }),
            el('span', { style: 'flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 3px' }, [
              el('span', { style: 'font-size: 15px; font-weight: 600' }, l.t),
              el('span', { style: 'font-size: 13px; line-height: 1.45; color: #A3ABAF' }, l.s),
              el('span', { style: MONO + 'font-size: 12px; color: #8E979C' }, f.t + ' · ' + size)
            ])
          ]);
        }))
      ]);
    }));

    var hint = document.getElementById('cfg-site-hint');
    if (hint) {
      if (m.siteOk) {
        hint.removeAttribute('role');
        hint.style.cssText = 'font-size: 13px; line-height: 1.5; color: #8E979C';
        fill('cfg-site-hint', ['Every key of this broker starts with ', code('wy/' + m.site + '/'), '. Lowercase letters, digits and hyphens.']);
      } else {
        hint.setAttribute('role', 'alert');
        hint.style.cssText = 'font-size: 13px; line-height: 1.5; color: #F3A766';
        fill('cfg-site-hint', 'Use lowercase letters, digits and hyphens, starting with a letter, 31 characters at most. The files below use “plant” until then.');
      }
    }
    var input = document.getElementById('site-name');
    if (input) input.setAttribute('aria-invalid', m.siteOk ? 'false' : 'true');

    var status = fill('cfg-status', [
      el('span', { style: 'padding: 3px 10px; border-radius: 999px; border: 1px solid ' + m.status.b + '; ' + MONO + 'font-size: 12px; color: ' + m.status.c }, m.status.t),
      el('span', { style: 'flex: 1 1 400px; min-width: 0; font-size: 14px; line-height: 1.6; color: #C5CBCE' }, m.note)
    ]);
    if (status) status.style.borderColor = m.status.b;

    fill('cfg-summary', [
      el('div', { style: 'padding: 20px; border-radius: 12px; background: #161A1D; border: 1px solid #252B30; display: flex; flex-direction: column; gap: 12px' }, [
        el('span', { style: MONO + 'font-size: 13px; color: #8E979C' }, 'file'),
        el('span', { style: MONO + 'font-size: 16px; font-weight: 600; word-break: break-all' }, m.file),
        el('span', { style: 'font-size: 14px; line-height: 1.6; color: #A3ABAF' }, ['Site ', code(m.site), ' · ' + plural(m.sel.length, 'link') + ': ' + m.summary]),
        m.sizeRows.length ? el('table', { style: 'width: 100%; border-collapse: collapse; font-size: 14px' }, [
          el('caption', { style: 'text-align: left; padding-bottom: 6px; ' + MONO + 'font-size: 12px; color: #8E979C' }, 'size, compressed; the broker as measured for linux/arm64, links from the release files'),
          el('tbody', null, m.sizeRows.map(function (r) {
            return el('tr', { style: 'border-top: 1px solid #252B30' }, [
              el('th', { scope: 'row', style: 'padding: 8px 0; text-align: left; font-weight: 400; color: #C5CBCE' }, r.k),
              el('td', { style: 'padding: 8px 0; text-align: right; ' + MONO + 'color: #ECE9E1' }, r.v)
            ]);
          }))
        ]) : null
      ]),
      m.today.length ? el('div', { style: 'padding: 20px; border-radius: 12px; background: #161A1D; border: 1px solid #2F5A51; display: flex; flex-direction: column; gap: 10px' }, [
        el('span', { style: 'font-size: 15px; font-weight: 600' }, 'Your link files, published today'),
        el('ul', { style: 'list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 6px' }, m.today.map(function (f) {
          return el('li', { style: 'display: flex; justify-content: space-between; gap: 12px; ' + MONO + 'font-size: 13px' }, [
            el('a', { href: f.url, style: 'word-break: break-all' }, f.name),
            el('span', { style: 'color: #8E979C; white-space: nowrap' }, f.size)
          ]);
        })),
        el('span', { style: 'font-size: 13px; line-height: 1.5; color: #8E979C' }, 'Each one is in SHA256SUMS of the release and has build provenance.')
      ]) : null
    ]);

    var box = function (label, text, tall) {
      return el('div', { style: 'display: flex; flex-direction: column; gap: 8px' }, [
        el('span', { style: MONO + 'font-size: 13px; color: #8E979C' }, label),
        el('pre', {
          tabindex: '0', role: 'region', 'aria-label': label,
          style: PRE + (tall ? 'max-height: 520px; overflow: auto; line-height: 1.6' : 'overflow-x: auto; line-height: 1.7')
        }, text)
      ]);
    };
    fill('cfg-files', [
      m.image ? el('div', { style: 'padding: 20px; border-radius: 12px; background: #161A1D; border: 1px solid #252B30; display: flex; flex-direction: column; gap: 16px' }, [
        el('span', { style: 'font-size: 16px; font-weight: 600' }, 'The image will be put together in your browser'),
        el('ol', { style: 'list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 10px' }, m.imgSteps.map(function (s) {
          return el('li', { style: 'padding: 14px; border-radius: 10px; border: 1px solid #2A3136; background: #0E1113; display: flex; flex-direction: column; gap: 6px' }, [
            el('span', { style: MONO + 'font-size: 12px; color: ' + ACCENT }, s.n),
            el('span', { style: 'font-size: 14px; font-weight: 600' }, s.t),
            el('span', { style: 'font-size: 13px; line-height: 1.45; color: #A3ABAF' }, s.s)
          ]);
        })),
        el('span', { style: 'font-size: 13px; line-height: 1.6; color: #8E979C' }, ['The image builder will put the image together in your browser from the release\'s base image, your ', code('wyrmd.json5'), ' and your choice of links. Nothing you choose is uploaded.']),
        el('span', { style: 'align-self: flex-start; padding: 10px 14px; border-radius: 10px; border: 1px solid #3A4249; font-size: 14px; line-height: 1.5; color: #C5CBCE' }, 'Not built yet: the base images and the builder are planned, so there is nothing to download today.')
      ]) : null,
      box('commands', m.commands, false),
      m.docker ? box('compose.yaml', m.compose, true) : null,
      box('wyrmd.json5', m.config, true)
    ]);
  }

  var siteInput = document.getElementById('site-name');
  if (siteInput) {
    siteInput.addEventListener('input', function () {
      set({ site: siteInput.value.trim().toLowerCase() });
    });
    siteInput.addEventListener('change', function () {
      siteInput.value = siteInput.value.trim().toLowerCase();
    });
    state.site = siteInput.value.trim().toLowerCase() || state.site;
  }
  // For the test of the generated files (tool/site/test_install.js): a hook
  // that only a test page defines.
  if (typeof window.wyrmInstallTest === 'function') {
    window.wyrmInstallTest({ state: state, model: model, render: render, PATHS: PATHS, TARGETS: TARGETS, PRESETS: PRESETS, LINKS: LINKS });
  }
  render();
})();
