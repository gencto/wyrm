# GitHub wiki and community files Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The repository's GitHub wiki holds the same documentation as `https://wyrm.gencto.uk/docs/`, generated from the repository and kept in step by CI, and the repository passes GitHub's Community Standards checklist (Insights ▸ Community Standards).

**Architecture:** One source: `docs/`, `spec/`, `docs/adr/` and the root `README.md`. A generator `tool/wiki/build.py` reuses the site generator's own rules (`tool/site/build.py`: the section list, the excluded files and directories, the finding-ID scrub, the deny-list when present) by importing them, never by copying them, and writes GitHub wiki pages (flat page names, `_Sidebar.md`, `_Footer.md`, `Home.md`, images under `img/`). A workflow pushes the result to `gencto/wyrm.wiki.git` on every change of the sources on `main`; a pull request only builds and checks it. Community files are plain repository files.

**Tech Stack:** Python 3 (standard library only, as `tool/site/build.py`), GitHub Actions, GitHub wiki (Gollum, GitHub-flavoured Markdown).

**Spec:** owner request 2026-11-28 ("a GitHub wiki at parity, a filled community section"); the site's own rules in `tool/site/build.py` and `site/README.md`; memory rules: the repo is public, security findings stay in private advisories, no reference product named.

## Global Constraints

- Parity: every page the site's docs have (guides by section, the spec parts, the ADR index and every ADR the site publishes) is a wiki page with the same text; nothing the site leaves out (`EXCLUDED_FILES`, `EXCLUDED_DIRS`: `docs/backlog.md`, `docs/studio.md`, `docs/rust-rules.md`, ADR 0031, `docs/superpowers/`, `docs/security/`; pages with a deny-list word) is in the wiki.
- One source of rules: the wiki generator imports `tool/site/build.py` (`tracked_files`, `excluded_reason`, `SECTION_GUIDES`, `SPEC_ORDER`, the finding-ID scrub, `DENIED`); it does not edit that file and does not copy its tables. (Another branch, `feat/image-builder-page`, edits `tool/site/build.py`; an import keeps the two apart.)
- The wiki is generated: every page ends with a footer naming its source file and commit, and saying to change the source in the repository; a hand edit in the wiki is overwritten by the next sync.
- Links: a link between two published docs becomes a wiki link to the page; a link to any other repository file becomes an absolute `https://github.com/gencto/wyrm/blob/main/<path>` link; a link to a page the wiki leaves out becomes plain text, never a dead link; anchors are kept with GitHub's anchor rules.
- Images: `docs/img/*` files the pages show are copied into the wiki repository under `img/` and linked relatively.
- The sync never deletes the wiki's own history; it replaces the generated pages and removes generated pages whose source is gone (a manifest file `_generated.txt` in the wiki lists them; a page not in it is left alone).
- No secrets in the workflow beyond `GITHUB_TOKEN` with `contents: write` on that job only; it fails with a clear message when the wiki repository does not exist yet (GitHub creates it only when the first page is saved in the web UI).
- Community files in English; the Code of Conduct is the Contributor Covenant 2.1 text with the contact set to the repository's private vulnerability reporting / owner contact the owner chooses (no personal e-mail in the file unless the owner gives one).
- Latest versions of actions, pinned by commit SHA with the version in a comment, as the other workflows.

## Review Focus

1. **A page the site excludes leaks into the wiki** (ADR 0031, `docs/security/`, a finding ID in prose): the wiki build must fail the same way the site build does. → Task 1 test `excluded_sources_never_become_pages` and `finding_ids_are_scrubbed`.
2. **Dead links after the flattening** (two guides with the same base name under different folders, links with anchors, `../spec/02-meta.md#…` from an ADR): every link in the generated wiki resolves to a generated page, an image in `img/`, or an absolute URL. → Task 1 check `--check` over the output, run in CI on every PR.
3. **The wiki repository does not exist yet** (wiki enabled, no page saved): the sync job fails with the exact step the owner takes, not a git error. → Task 2 test of the script's message (dry run against a missing remote).
4. **A stale generated page** after a doc is renamed or removed: the sync removes it, and leaves pages written by hand (not in `_generated.txt`). → Task 1 test `a_page_whose_source_is_gone_is_removed_and_a_hand_page_stays`.
5. **A Markdown construct the site renders and GitHub's wiki does not** (mdBook-only syntax the site generator emits: `{{#include}}`, HTML the site adds, figure captions): the wiki output uses plain GFM. → Task 1 test on a guide with a figure and a table.

---

### Task 1: The wiki generator `tool/wiki/build.py`

**Files:**
- Create: `tool/wiki/build.py`, `tool/wiki/test_build.py` (unittest, standard library), `tool/wiki/README.md` (what it does, how to run, what the owner sets in the wiki)

**Interfaces:**
- Produces: `python3 tool/wiki/build.py --out <dir>` writes the wiki pages into `<dir>` (a checkout of the wiki repository or an empty directory) and the manifest `_generated.txt`; `python3 tool/wiki/build.py --check <dir>` checks every link and image of a built wiki; exit 1 with the list of problems. Page names: `Home`, one page per guide named by its title in the site's section order (`Broker`, `Modbus`, …; a name clash gets the section as a prefix), `Spec-01-keyspace`…, `ADR-0001-…`, `Decisions` (the ADR index). `_Sidebar.md` lists the sections in the site's order with the site's numbers (`01 Overview` …), `_Footer.md` links the site and the repository.
- Consumes: from `tool/site/build.py` (imported as a module): `tracked_files`, `excluded_reason`, `SECTION_GUIDES`, `SPEC_ORDER`, `FALLBACK_SECTION`, `DENIED`/`denied_word`, the finding-ID scrub, `readme_intro`. If a function needed is private or entangled with mdBook output, the generator wraps it; it does not change `tool/site/build.py` (ruling: an import, not an edit).

- [ ] **Step 1: Write the failing tests** in `tool/wiki/test_build.py` against a fixture tree (a temporary repo with a few docs, a spec part, two ADRs, one excluded ADR, an image): `every_published_doc_becomes_a_page`, `excluded_sources_never_become_pages`, `finding_ids_are_scrubbed` (same output as the site's scrub for the same text), `links_between_pages_become_wiki_links` (`[x](modbus.md#data-types)` → `[x](Modbus#data-types)`), `links_to_other_files_become_blob_urls`, `links_to_left_out_pages_become_text`, `images_are_copied_and_linked`, `a_page_whose_source_is_gone_is_removed_and_a_hand_page_stays`, `the_sidebar_follows_the_sites_sections`, `every_page_has_the_generated_footer` (source path and commit).
- [ ] **Step 2: Run** `python3 -m unittest tool/wiki/test_build.py` — fail.
- [ ] **Step 3: Implement** `tool/wiki/build.py` (standard library only).
- [ ] **Step 4: Run** the tests — pass. Run on the real repository: `python3 tool/wiki/build.py --out /tmp/wiki && python3 tool/wiki/build.py --check /tmp/wiki` — no problems; compare the page list with the site's `site/src/SUMMARY.md` after `python3 tool/site/build.py` (same set of sources; write the comparison into the commit message).
- [ ] **Step 5: Commit** `wiki: the GitHub wiki generated from docs, spec and ADRs`.

### Task 2: The sync workflow

**Files:**
- Create: `.github/workflows/wiki.yml`, `tool/wiki/sync.sh` (clone the wiki repo with the token, run the generator into it, commit as `github-actions[bot]` with the source commit in the message, push; a clear error when the wiki repo is missing)

**Interfaces:**
- Consumes: Task 1's CLI.
- Produces: on `push` to `main` with the same path filters as `.github/workflows/site.yml` plus `tool/wiki/**`: build, check, sync. On `pull_request`: build and check only. `workflow_dispatch` runs a sync by hand. `permissions: contents: read` at the top, `contents: write` on the sync job only. Concurrency group `wiki`, never cancelled half way.

- [ ] **Step 1: Write** `tool/wiki/sync.sh` with `--dry-run` (builds and shows `git status` of the wiki checkout without pushing); test by hand against the real wiki in dry-run once the owner created the first page; test the missing-repo message against a non-existent remote.
- [ ] **Step 2: Write** `.github/workflows/wiki.yml`; run `actionlint` (Docker `rhysd/actionlint`) — clean; shellcheck on `sync.sh` — clean.
- [ ] **Step 3: Commit** `wiki: sync the generated wiki on every change of the docs`.

### Task 3: Community files

**Files:**
- Create: `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1, contact as the owner chooses), `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/feature_request.yml`, `.github/ISSUE_TEMPLATE/link_request.yml` (a new device/protocol link: protocol, devices, documentation, simulator), `.github/ISSUE_TEMPLATE/config.yml` (blank issues off; contact links: security → the repository's private vulnerability reporting, questions → the docs site and the wiki), `.github/PULL_REQUEST_TEMPLATE.md` (what, why, how verified, checklist from `CONTRIBUTING.md`: fmt, clippy, tests, `tool/check_rust_rules.py`, spec + fixtures when `spec/` changes), `SUPPORT.md` (where to ask, what to include)
- Modify: `CONTRIBUTING.md` (link the Code of Conduct and the templates), `README.md` (a "Community" line: wiki, docs, how to contribute, how to report a vulnerability)

- [ ] **Step 1: Write** the files; the forms' fields match what a maintainer needs for this project (version of `wyrmd`, platform/board, link and its version, `wyrmd.json5` excerpt without secrets, log with `RUST_LOG`).
- [ ] **Step 2: Check**: `gh api repos/gencto/wyrm/community/profile` after merge lists every item as present (record the output in the PR); before merge, validate the YAML forms with `python3 -c 'import yaml…'` or the GitHub issue-form schema.
- [ ] **Step 3: Commit** `community: code of conduct, issue and pull request templates, support`.

## What the owner does (once)

1. Open the repository's **Wiki** tab and save any first page (GitHub creates the wiki repository only then); the sync replaces it with `Home`.
2. In **Settings ▸ General ▸ Features ▸ Wikis**, tick **Restrict editing to collaborators only**, so the generated wiki is not edited by hand by others.
3. Optional: turn on **Discussions** for questions (the templates then point there instead of the docs).
4. Choose the contact for the Code of Conduct (the private vulnerability reporting form, or an e-mail address).
