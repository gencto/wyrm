# The WYRM home site

https://wyrm.gencto.uk is built from this repository on every merge to `main`.

| Address | What | Source |
|---|---|---|
| `/` | the home page | `site/home/index.html` (template) |
| `/install/` | the install page with its configurator | `site/install/index.html` (template), `site/assets/install.js` |
| `/docs/` | the documentation, an mdBook | `docs/`, `docs/adr/`, `spec/`, the root `README.md`, `links/official.json` |
| `/404.html` | the page for a missing address | `site/404.html` (template) |
| `/assets/` | fonts, CSS, images, scripts | `site/assets/` |

The site loads nothing from another host: the fonts (`site/assets/fonts/`,
licences in `LICENSES` beside them), the images and the scripts are files of
the site. `--check` fails on a page that loads a file from elsewhere.

## The designed pages

The home page, the install page and the 404 page are the owner's design as
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
   - `SUMMARY.md` with the sections Start, Guides, Links (connectors),
     Operations, Architecture decisions and Specification;
   - the docs landing page `index.md`: the first paragraph and the status of
     the README, the official links from `links/official.json`, the latest ADRs
     and the latest entries of `spec/CHANGELOG.md`.
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
   on a placeholder left in a designed page, on a file at a reserved path, and
   on an official link that is missing from the home page or from the table of
   the docs. The links that `install.js` makes in the browser (the files of
   the links release) are outside this check.

The theme (`site/theme/`) gives the book the look of the design: `wyrm.css`
(colours, type, tables, code; every mdBook theme gets the same dark look and
the theme menu is hidden), `header.hbs` (the top bar of the site), `head.hbs`
(the shared fonts) and `fonts/fonts.css` (takes the place of mdBook's own
fonts). There is no `index.hbs` override, so an mdBook upgrade needs no merge.

The workflow `.github/workflows/site.yml` runs these steps on each pull request
that touches the sources (build and check only) and on each push to `main`
(build, check and deploy to GitHub Pages). It uses the mdBook release binary of
the version in the workflow, checked against its SHA-256.

Not on the site: `docs/superpowers/**` (agents' work plans), `docs/security/**`
and ADR 0031 (security weaknesses stay private), `docs/backlog.md` (work list),
`docs/studio.md` (the Studio build plan) and `docs/rust-rules.md` (contributor
rules). An ADR whose main content is a list of open security weaknesses is left
out the same way. The list is `EXCLUDED_FILES` and
`EXCLUDED_DIRS` in the generator. A new `docs/*.md` that no section lists goes
to Guides, and the generator prints a warning: add it to a section list. A
designed page must not link an excluded file either, on the site or on GitHub.

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

The site path `/start` is kept free for the image builder of ADR 0051: the
generator writes nothing there and `--check` fails if something is.

## Preview

Install mdBook 0.5 (`cargo install mdbook --locked`, or a release binary), then:

```bash
python3 tool/site/build.py && mdbook build site
python3 tool/site/build.py --check site/dist
python3 -m http.server 8000 --directory site/dist
```

Open http://localhost:8000. Run the first line again after you change a source
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
5. Run the workflow **site** once (Actions → site → Run workflow), or merge a
   change to the sources.
