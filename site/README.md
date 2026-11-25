# The WYRM home site

https://wyrm.gencto.uk is built from this repository. Nobody edits it by hand:
to change a page, change its source in `docs/`, `docs/adr/`, `spec/`,
`links/official.json` or the root `README.md`, and merge to `main`.

## How it is built

1. `python3 tool/site/build.py` writes `site/src/` (git-ignored) from the files
   that git tracks:
   - the root `README.md` as the Overview, and `docs/README.md` as the
     documentation map;
   - the guides `docs/*.md`, the ADRs `docs/adr/*.md`, the spec `spec/*.md` and
     `spec/CHANGELOG.md`, at the same paths as in the repository (a `README.md`
     becomes `index.md`);
   - `SUMMARY.md` with the sections Start, Guides, Links (connectors),
     Operations, Architecture decisions and Specification;
   - the landing page `index.md`: the first paragraph and the status of the
     README, the official links from `links/official.json`, the latest ADRs and
     the latest entries of `spec/CHANGELOG.md`;
   - the files of `site/static/` into the site root (`CNAME`).
2. A link to a file of the repository that is not on the site (source code,
   examples) goes to the file on GitHub. A link to a file left out on purpose
   (the list below) becomes plain text: no link, no GitHub URL. A link to a
   file that does not exist stops the build.
3. `mdbook build site` writes `site/book/`.
4. `python3 tool/site/build.py --check site/book` reads every HTML page and
   fails on a link to a missing page or a missing `#id`, on a page from the
   excluded list, and on an official link that is not in the landing table.

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
to Guides, and the generator prints a warning: add it to a section list.

Security findings stay private, fixed ones too: the generator reads the
finding IDs from the sources it leaves out (ADR 0031 and `docs/security/*.md`:
the first column of a table headed `ID`, and headings `### <ID> — …`). It
removes each ID from the pages it copies, with the wrapping that only served it
(`(security review <ID>)` → `(security review)`), outside code blocks. A short
ID such as a letter and one digit counts only after "audit" or "review" in its
clause, because the same token names other things. `--check` fails if an ID is
left in the built site.

An optional local deny-list, `tool/site/denied-words.local` (git-ignored, one
word per line), leaves out every page that holds one of its words; the build
stops if the landing page holds one. Without the file the check is skipped.

A link to the folder `docs/adr/` lands on the generated page of all decisions
(`docs/adr/index.md`).

The site path `/start` is kept free for the image builder of ADR 0051.

## Preview

Install mdBook 0.5 (`cargo install mdbook --locked`, or a release binary), then:

```bash
python3 tool/site/build.py && mdbook serve site
```

Open http://localhost:3000. Run the generator again after you change a source
file: `mdbook serve` watches `site/src/`, not `docs/`.

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
