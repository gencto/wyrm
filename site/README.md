# The WYRM home site

https://wyrm.gencto.uk is built from this repository on every merge to `main`.

| Address | What | Source |
|---|---|---|
| `/` | the home page | `site/home/index.html` (template) |
| `/install/` | the install page with its configurator | `site/install/index.html` (template), `site/assets/install.js` |
| `/start/` | the image builder: a board image made in the browser (ADR 0051 §4) | `site/start/index.html` (template), `site/assets/start.js`, the WebAssembly of `crates/wyrm-image-web` |
| `/docs/` | the documentation, an mdBook | `docs/`, `docs/adr/`, `spec/`, the root `README.md`, `links/official.json` |
| `/404.html` | the page for a missing address | `site/404.html` (template) |
| `/assets/` | fonts, CSS, images, scripts | `site/assets/` |

The site loads nothing from another host: the fonts (`site/assets/fonts/`,
licences in `LICENSES` beside them), the images and the scripts are files of
the site. `--check` fails on a page that loads a file from elsewhere.

## The designed pages

The home page, the install page, the image builder page and the 404 page are the owner's design as
plain static HTML: the markup carries the design's inline styles, and
`site/assets/site.css` adds the base, the focus styles, the motion and the
rules for small screens. There is no build step for them except the
placeholders.

A template holds `{{name}}` placeholders. `tool/site/build.py` fills them with
facts of the repository, so a page does not go stale:

| Placeholder | Value | Read from |
|---|---|---|
| `{{root}}` | the path to the site root (`""`, `../`, `/` for 404) | the page's place |
| `{{version}}` | the workspace version | `Cargo.toml` |
| `{{zenoh_version}}`, `{{zenoh_minor}}` | the pinned Zenoh version | `Cargo.toml` |
| `{{block_types}}` | the number of dataflow block types | `README.md` ("N block types") |
| `{{modbus_binary_mib}}`, `{{modbus_image_mib}}`, `{{modbus_idle}}` | the measured Modbus link image: binary, compressed image, idle memory | `deploy/docker/README.md` (table "Measured") |
| `{{spec_version}}` | the newest spec version | `spec/CHANGELOG.md` |
| `{{spec_parts}}`, `{{fixtures_count}}` | the spec parts and the CBOR fixtures | files of `spec/` |
| `{{adr_count}}`, `{{adr_latest}}` | the decisions on the site, the newest one | `docs/adr/` |
| `{{link_crates}}` | the link crates | `links/*/Cargo.toml` |
| `{{links_count}}` | the official links | `links/official.json` |
| `{{chips_<category>}}` | the official links of one category, each a link to its guide | `links/official.json` |
| `{{docs_sections}}` | the sections of the docs | the generator |
| `{{release_tag}}`, `{{release_url}}`, `{{release_download}}` | the links release the install page offers | `site/install/release.json` |
| `{{install_data}}` | the official links and the file sizes of that release, as JSON for `install.js` | `links/official.json`, `site/install/release.json` |

An unknown placeholder stops the build. So does a category of
`links/official.json` that the home page has no `{{chips_…}}` for, and a fact
the generator cannot read. Write a link to a page of the site as
`{{root}}docs/modbus.html`; `--check` follows it.

To change a text of a designed page, edit its template. To change a number,
change its source: the template holds no number that the repository knows.

`site/install/release.json` records the file sizes of the links release that
the install page offers. After a new `links-v*` release, record it again:

```bash
gh release view <tag> -R gencto/wyrm --json tagName,assets \
  -q '{tag: .tagName, assets: ([.assets[] | select(.name | endswith(".zip")) | {(.name): .size}] | add)}' \
  > site/install/release.json
```

## The documentation

Nobody edits the docs on the site by hand: to change a page, change its source
and merge to `main`.

1. `python3 tool/site/build.py` writes `site/src/` (git-ignored) from the files
   that git tracks:
   - the root `README.md` as the Overview (`overview.md`), and `docs/README.md`
     as the documentation map (`map.md`);
   - the guides `docs/*.md` at the top of the book (`docs/modbus.md` is
     `/docs/modbus.html`), the ADRs under `adr/`, the spec `spec/*.md` and
     `spec/CHANGELOG.md` under `spec/` (a `README.md` becomes `index.md`);
   - the figures `docs/img/*` under `img/`;
   - `SUMMARY.md` with the numbered sections (below);
   - the docs landing page `index.md`: the first paragraph and the status of
     the README, the sections with their pages, the official links from
     `links/official.json`, the latest ADRs and the latest entries of
     `spec/CHANGELOG.md`;
   - what the design's pages have and plain Markdown lacks (below): the
     section number above each title, figures with captions, "More:" rows.
   The same run writes the rest of the site into `site/dist/` (git-ignored):
   the designed pages, `site/assets/` as `/assets/`, the files of
   `site/static/` (`CNAME`) and a redirect stub at each address a page had
   while the docs were at the site root (`/overview.html`, `/spec/…`).
2. A link to a file of the repository that is not on the site (source code,
   examples) goes to the file on GitHub. A link to a file left out on purpose
   (the list below) becomes plain text: no link, no GitHub URL. A link to a
   file that does not exist stops the build. A line of badges is dropped: a
   badge is an image from another host.
3. `mdbook build site` writes `site/dist/docs/` with the theme of
   `site/theme/`.
4. `python3 tool/site/build.py --check site/dist` reads every HTML page of the
   site, the designed pages too. It fails on a link to a missing page or a
   missing `#id`, on a file loaded from another host, on a page from the
   excluded list, on a security finding ID, on a word of the local deny-list,
   on a placeholder left in a designed page, on a file in `/start/` other than
   its page and `images/`, on a missing file of the WebAssembly, and
   on an official link that is missing from the home page or from the table of
   the docs. The links that `install.js` makes in the browser (the files of
   the links release) are outside this check.

5. `node tool/site/test_install.js` runs `site/assets/install.js` against a DOM
   stub with the data of the built page, over every path, target, mode and
   set of links. It fails if a `wyrmd.json5` with a link process (a built-in
   driver in process mode, a process package, or a link container) has no
   `tls/` listener, if a config sets `insecure_plaintext`, if a key is not in
   the test's list or is not a field of the broker's config, if a planned
   path shows a command that could be run, if the page opens on a planned
   path, or if a config for a board image names the setup file or the seed
   directory otherwise than the constants `SETUP_FILE` and `SEED_DIR` of
   `crates/wyrm-image/src/region.rs` (the test reads them from that file). Node 18+, no dependencies.

6. `node tool/site/test_start.mjs` runs the functions of `site/assets/start.js`
   with the built WebAssembly against a fixture index and a small base image
   of one gzip member: a download of another size or SHA-256 is refused and
   not cached, the assembly changes only the region and gives one gzip
   member with the right ISIZE, an image of another length is refused, the
   replace step streams, the file name is plain, and on a DOM stub the
   Download button waits for "I wrote it down", a site the device
   refuses shows the device's words and no code, and a changed choice calls
   a download in progress off. `--assemble <choices.json> <out.img.gz>`
   makes a real image with the same code instead
   (`packaging/images/smoke.sh --assembled` boots it). Node 20+, no
   dependencies.

7. `python3 tool/site/test_fetch_images.py` runs `tool/site/fetch_images.py`
   against releases written into a temporary directory: only the listed
   boards are copied, a file that does not match the index or `SHA256SUMS` is
   refused and leaves nothing behind, a name that is no plain file name is
   refused, the 900 MiB cap holds, and no release writes nothing.

### Sections

The book has nine numbered sections. The side menu shows the number before the
name (`03 Links`) and each page shows it above its title.

| | Section | Pages |
|---|---|---|
| 01 | Overview | the root `README.md`, `docs/README.md` (the documentation map) |
| 02 | Architecture | the broker and the services every `wyrmd` has inside: `broker`, `history`, `scheduler`, `alarm`, `dql`, `uplink` |
| 03 | Links | `links` and one guide per protocol or service: `modbus`, `bacnet`, `knx`, `opcua`, `s7`, `snmp`, `http`, `prometheus`, `filestores`, `messenger`, `telegram`, `slack` |
| 04 | Dataflow | `flow-blocks` |
| 05 | Studio and assistants | a reading list (below), `claude`, `mcp`, `agent` |
| 06 | Security | a reading list (below) |
| 07 | Operations | `operations`, `backups` |
| 08 | Specification | `spec/README.md`, the spec parts, `spec/CHANGELOG.md` |
| 09 | Decisions | the page of all decisions, and the ADRs folded under it |

The list is `SECTION_GUIDES` in the generator. A new `docs/*.md` that no
section lists goes to Architecture, and the generator prints a warning: add it
to a section.

Studio and Security have no guide in `docs/` that is on the site
(`docs/studio.md` and `docs/security/` are left out, see below). Each opens
with a reading list the generator writes (`TOPICS`: `/docs/topics/studio.html`,
`/docs/topics/security.html`): one paragraph, the decisions on the subject and
the pages to read with them. The paragraph says only what the README and the
listed pages say. An ADR that is left out of the site is left out of the list.

### What the generator adds to a page

The sources stay plain Markdown that GitHub renders. The copy in the book gets:

- **The section number**, a line above the title (`03 LINKS`). The first
  paragraph under the title of a guide is set as its lead; under the title of
  an ADR it is the status line.
- **"More:" rows.** At the end of the intro and of each `##` section of a
  guide, one row links the ADRs and spec parts that the section names: by a
  link, or as `ADR 0004`, `spec 01`, `spec/01`. An ADR or a spec part gets one
  row at its end. A row has at most eight links, in the order the text names
  them. A name inside a code block or a code span does not count.
- **Figures.** A paragraph that is one image, with a paragraph in italics
  right under it, becomes a figure with that caption:

  ```markdown
  ![What the picture shows, for a reader who cannot see it](img/key-anatomy.svg)

  *The caption. One or two sentences.*
  ```

### Figures

The figures are SVG files in `docs/img/`, written by hand: plain shapes and
text, no script, no font file, nothing from another host. Each one draws its
own dark panel (`#161A1D`, a 12 px corner), so the same file reads on the site
and on GitHub's light and dark themes. Reference one with a standard Markdown
image, relative to the page (`img/x.svg` from `docs/x.md`, `../img/x.svg` from
an ADR, `docs/img/x.svg` from the root README).

A figure states facts. Before you add or change one, check every label against
`spec/` and the guide it sits in, and leave out what you cannot check. The
colours and sizes: boxes `#0E1113` with a `#3A4249` edge and a 10 px corner,
the one box that matters with an `#E8893A` edge, labels 13 px in the system
sans or mono stack, arrows `#8E979C` 2 px.

The Mermaid chart of the root README became `docs/img/overview.svg`: mdBook
does not draw Mermaid, and a script for it would be one more thing to load.

### The docs theme

The theme (`site/theme/`) gives the book the look of the design:

- `wyrm.css`: colours, type, the frame (the sections as a card beside the
  text, a drawer below 1080 px), tables, code, figures, the page links. Every
  mdBook theme gets the same dark look and the theme menu is hidden.
- `header.hbs`: the top bar of the site. `head.hbs`: the shared fonts.
  `fonts/fonts.css` takes the place of mdBook's own fonts.
- `index.hbs`: the page template, a copy of mdBook 0.5.4's with a few changes,
  each marked `WYRM:` in a comment: the top bar above the menu and the text, a
  real `<button>` for the menu (mdBook has a `<label>`), a skip link, the two
  page links with titles, `defer` on the scripts, and one script at the end
  (the button, the drawer, the fold arrows as buttons, the scroll position).

`book.toml` folds the decisions under "All decisions" (`fold`), and turns the
Rust playground off: with it, mdBook's script asks `play.rust-lang.org` for a
list on every page that shows Rust code.

**To refresh `index.hbs` for another mdBook version:**

1. Make a scratch book with the new version: `mdbook init --theme /tmp/book`.
2. Compare `/tmp/book/theme/index.hbs` with the one of the version named at
   the top of `site/theme/index.hbs` (`git diff --no-index`, or the mdBook
   repository's history of `crates/mdbook-html/front-end/templates/index.hbs`).
3. Apply what changed to `site/theme/index.hbs`. Keep each block marked
   `WYRM:`. Change the version named at the top.
4. Change `MDBOOK_VERSION` and `MDBOOK_SHA256` in
   `.github/workflows/site.yml`.
5. Build, run `--check`, and try the menu button, the drawer on a narrow
   window, the search (`/`) and the arrow keys.

mdBook's own script (`book.js`) is not replaced. One line of it registers an
`unload` handler, which the browser reports in the console as a permissions
policy violation; that message is mdBook's.

The workflow `.github/workflows/site.yml` runs these steps on each pull request
that touches the sources (build and check only, without images) and on each
push to `main` or run on `main` (build, copy the images, check and deploy to
GitHub Pages; `images-release.yml` starts such a run after it publishes). It
uses the mdBook and `wasm-bindgen` release binaries of the versions in the
workflow, each checked against its SHA-256, and the Rust toolchain with the
`wasm32-unknown-unknown` target for the page's WebAssembly.

Not on the site: `docs/superpowers/**` (agents' work plans), `docs/security/**`
and ADR 0031 (security weaknesses stay private), `docs/backlog.md` (work list),
`docs/studio.md` (the Studio build plan) and `docs/rust-rules.md` (contributor
rules). An ADR whose main content is a list of open security weaknesses is left
out the same way. The list is `EXCLUDED_FILES` and
`EXCLUDED_DIRS` in the generator. A designed page must not link an excluded
file either, on the site or on GitHub.

Security findings stay private, fixed ones too: the generator reads the
finding IDs from the sources it leaves out (ADR 0031 and `docs/security/*.md`:
the first column of a table headed `ID`, and headings `### <ID> — …`). It
removes each ID from the pages it copies, with the wrapping that only served it
(`(security review <ID>)` → `(security review)`), outside code blocks. A short
ID such as a letter and one digit counts only after "audit" or "review" in its
clause, because the same token names other things. `--check` fails if an ID is
left in the built site.

An optional local deny-list, `tool/site/denied-words.local` (git-ignored, one
word per line), leaves out every docs page that holds one of its words; the
build stops if the docs landing page or a designed page holds one, and
`--check` reads every built page for them. Without the file the check is
skipped.

A link to the folder `docs/adr/` lands on the generated page of all decisions
(`/docs/adr/`).

### The image builder page

`/start/` builds a board image in the browser. `site/assets/start.js` reads
`start/images/index.json` (format `wyrm-images/1`) and
`start/images/catalog.json` (the links the images offer) beside the page,
and offers each board whose entry has a `download`. Without
`start/images/index.json` the page says that no image is published yet and
points to `wyr image build`. The images are not in the repository: the
deploy copies them there. After `build.py` (which deletes `site/dist`),
`tool/site/fetch_images.py` takes the latest `images-v*` release and copies
the `.img.gz` and `.manifest` of each board that
`packaging/images/boards.json` marks `listed`, `catalog.json`, and an
`index.json` with those boards' entries only: a filtered copy of the
release's index, not the published file. It checks each file against the
index (and the index and catalog against `SHA256SUMS`) and fails above
900 MiB. With no such release it writes nothing. A pull request builds the
site without images. The images release (`images-release.yml`) starts the
workflow `site` on `main` after it publishes. The install page asks for
`start/images/index.json` too: when it is there, its path "USB or SD image"
says that it works today and opens the page.

- The choices become the 4 MiB config region in the WebAssembly of
  `crates/wyrm-image-web` (`wyrm_image::Choices::files`, the code `wyr image
  build --choices` runs). `tool/site/wasm.sh` builds it into
  `site/dist/assets/wasm/`; `build.py` runs it (it needs Rust, the target
  `wasm32-unknown-unknown` and `wasm-bindgen-cli` of the pinned version, which
  the script installs and checks again) and `--check` fails without its two
  files. CI builds it first with `tool/site/wasm.sh <dir>` and gives it to
  `build.py --wasm-from <dir>`.
- Build checks the choices (`check_choices`; a refusal is shown at its
  field), makes the setup code from 16 bytes of `crypto.getRandomValues`
  and shows it once, with its QR code. Download stays off until "I wrote it
  down" is ticked. A change of a choice voids the build and its code.
- Download fetches the base image from this site, checks its size and
  SHA-256 against the entry's `download`, and keeps it in the Cache API (the
  only thing the page stores; a browser that refuses storage just downloads
  again). It streams the image: `DecompressionStream`, the region's bytes
  replaced at `config_offset`, `CompressionStream`. The file it saves is one
  gzip member whose ISIZE is the image size, and every byte outside the
  region is that of the base image. At its peak the page holds about 3 to 4
  times the compressed size of the download (the checked download, its copy
  in a Blob, the finished file), never the raw image. A new build or a
  changed choice calls a download or an assembly in progress off.
- The page asks its own origin only. It writes nothing to `localStorage`,
  `sessionStorage`, cookies or the URL.

`/start/` holds the page and `images/` only: `--check` fails on any other
file there, and no file of `site/static/` or `site/assets/` may take the
path.

## Preview

Install mdBook 0.5 (`cargo install mdbook --locked`, or a release binary), then:

```bash
python3 tool/site/build.py && mdbook build site
python3 tool/site/build.py --check site/dist
python3 -m http.server 8000 --directory site/dist
```

Run `node tool/site/test_install.js` after a change to `install.js`, and
`node tool/site/test_start.mjs` after a change to `start.js`. To try `/start/`
with an image, put a base image (`wyr image base`), its `index.json` and a
`catalog.json` (`packaging/images/catalog.py`) into `site/dist/start/images/`
after the build, or run `python3 tool/site/fetch_images.py` (the latest
release) or `--from-dir <dir>` (a directory with a release's assets). Open
http://localhost:8000. Run the first line again after you change a source
file or a template. `mdbook serve site` shows the docs alone, without the top
bar's fonts and without the designed pages.

## One-time setup (repository owner)

1. In GitHub, open **Settings → Pages** and set **Source** to **GitHub Actions**.
2. On the same page, set **Custom domain** to `wyrm.gencto.uk` and save. A
   deployment from Actions does not read the `CNAME` file, so this setting is
   the one that counts.
3. In Cloudflare, in the DNS of `gencto.uk`, add a record `CNAME wyrm →
   gencto.github.io` with the proxy status **DNS only** (grey cloud), so GitHub
   can issue the certificate.
4. When GitHub shows the domain as checked, turn on **Enforce HTTPS**.
5. In **Settings → Environments → github-pages**, keep **Deployment branches**
   at `main` only, so no other branch can publish the site. The workflow
   deploys on a push to `main` and on a run on `main` (the images release
   starts one); this setting holds the same rule on GitHub's side.
6. Run the workflow **site** once (Actions → site → Run workflow), or merge a
   change to the sources.
