#!/usr/bin/env python3
"""Build the WYRM home site from the repository.

    python3 tool/site/build.py                 # write site/src/ and site/dist/
    mdbook build site                          # write site/dist/docs/
    python3 tool/site/build.py --check site/dist   # check the built site

The site has two parts. The designed pages (`/`, `/install/`, `404.html`) are
the templates `site/home/index.html`, `site/install/index.html` and
`site/404.html`: static HTML whose `{{name}}` placeholders this script fills
with facts of the repository, so a page never goes stale. The documentation
(`/docs/`) is an mdBook: the repository's `docs/`, `docs/adr/` and `spec/` are
the one source of truth. This script copies the guides, ADRs and the spec into
`site/src/` (generated, git-ignored), rewrites the links that leave the book to
GitHub, groups the pages into numbered sections, adds to each copy what the
design's pages have (the section number above the title, figures with
captions, "More:" rows) and writes `SUMMARY.md` and the docs landing page
`index.md`. Only files tracked by git are read. `--check` parses every HTML page of a built site and
fails on a link to a missing page or a missing `#id`, on a file loaded from
another host and on a security finding ID. Python 3.10+, standard library only.
"""

from __future__ import annotations

import argparse
import html
import html.parser
import json
import posixpath
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SITE = REPO / "site"
SRC = SITE / "src"        # the mdBook source, generated
DIST = SITE / "dist"      # the whole site; mdBook writes DIST/docs (book.toml)
DOCS = "docs"             # the place of the book in the site: /docs/
STATIC = SITE / "static"  # copied as is into the site root (CNAME)
ASSETS = SITE / "assets"  # copied as is to /assets/ (fonts, CSS, images, JS)
ORIGIN = "https://wyrm.gencto.uk"
# The designed pages: place in the site -> (template, path to the site root).
# 404.html is served for any missing path, so its links start at "/".
DESIGNED = {
    "index.html": (SITE / "home/index.html", ""),
    "install/index.html": (SITE / "install/index.html", "../"),
    "404.html": (SITE / "404.html", "/"),
}
# The docs were at the site root for a short time. A page whose address
# changed gets a stub at the old one (guides and ADRs kept theirs).
MOVED = ("overview.md", "spec/")
STUB = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Moved — WYRM</title>
<meta name="robots" content="noindex">
<link rel="canonical" href="{origin}/{target}">
<meta http-equiv="refresh" content="0; url={href}">
</head>
<body>
<p>This page moved to <a href="{href}">{origin}/{target}</a>.</p>
</body>
</html>
"""
# The file sizes of the links release the install page offers; see
# site/README.md for the command that records them.
RELEASE = SITE / "install/release.json"
GITHUB = "https://github.com/gencto/wyrm"
BLOB = f"{GITHUB}/blob/main/"
TREE = f"{GITHUB}/tree/main/"

# Paths of the site root the generator never writes: kept free for later
# pages (`/start`: the image builder of ADR 0051).
RESERVED = ("start",)

# Files under docs/ and spec/ that are not on the site, with the reason.
EXCLUDED_FILES = {
    "docs/backlog.md": "work list, not a guide",
    "docs/studio.md": "build plan of WYRM Studio, not a guide",
    "docs/rust-rules.md": "contributor code rules, not a user guide",
    "docs/adr/0031-security-review-2026-10-31.md":
        "tracks the findings of a security review; kept private",
}
EXCLUDED_DIRS = {
    "docs/superpowers/": "work plans and specs of agents",
    "docs/security/": "security reviews and threat notes",
}

# The numbered sections of the book, in the order of SUMMARY.md: the name, and
# the guides `docs/<name>.md` it holds. The side menu shows the number before
# the name (`01 Overview`) and each page shows it above its title. Overview,
# Specification and Decisions are filled from the README, `spec/` and
# `docs/adr/`. A new doc that is in no list lands in FALLBACK_SECTION (with a
# warning), so it never disappears from the site in silence.
SECTION_GUIDES = [
    ("Overview", []),
    # the broker and the services that every `wyrmd` has inside
    ("Architecture", ["broker", "history", "scheduler", "alarm", "dql", "uplink"]),
    ("Links", ["links", "modbus", "bacnet", "knx", "opcua", "s7", "snmp", "http",
               "prometheus", "filestores", "messenger", "telegram", "slack"]),
    ("Dataflow", ["flow-blocks"]),
    ("Studio and assistants", ["claude", "mcp", "agent"]),
    ("Security", []),
    ("Operations", ["operations", "backups"]),
    ("Specification", []),
    ("Decisions", []),
]
SECTIONS = [name for name, _ in SECTION_GUIDES]
FALLBACK_SECTION = "Architecture"
SPEC_ORDER = ["README", "01-keyspace", "02-meta", "03-val", "04-attachment",
              "05-methods", "06-flow-def", "CHANGELOG"]

# A section whose subject has no guide in `docs/` opens with a reading list
# the generator writes: the decisions and the spec parts that hold the rules.
# The sentences state only what the root README and the listed pages say. An
# ADR that is left out of the site is left out of the list too.
TOPICS = {
    "Studio and assistants": {
        "page": "topics/studio.md",
        "title": "WYRM Studio",
        "lead": "WYRM Studio is the app for the tree, the dataflows and the"
                " system of a site, written in Flutter. It works through the"
                " user gateway, as every other client of a person does. The"
                " decisions below say how it is built and what it needs from the"
                " broker; the guides of this section cover the AI assistants,"
                " which come in through the same gateway.",
        "adrs": ["0037", "0019", "0038", "0042", "0049", "0050"],
        "more": [("README.md", "#wyrm-studio", "Overview",
                  "how to start Studio with the demo"),
                 ("docs/broker.md", "#gateway", "Broker reference",
                  "the user gateway that Studio logs in to")],
    },
    "Security": {
        "page": "topics/security.md",
        "title": "Security",
        "lead": "Security is not optional in WYRM: TLS or mTLS on every"
                " connection except loopback, secrets never in the tree, and a"
                " signed permission token (`ptok`) that the responder checks on"
                " every write and action. The pages below hold the rules.",
        "adrs": ["0006", "0007", "0008", "0009", "0013", "0015", "0018", "0046",
                 "0050"],
        "more": [("spec/04-attachment.md", "#ptok-v1", "Specification 04",
                  "the permission token and the order of its checks"),
                 ("docs/links.md", "#13-trust-and-security", "Links",
                  "who can install a link and what a package may do"),
                 ("SECURITY.md", "", "SECURITY.md",
                  "how to report a vulnerability")],
    },
}
TOPIC_PAGES = {t["page"] for t in TOPICS.values()}

# Figures: the SVG files of `docs/img/` that the guides show. They are copied
# into the book (`/docs/img/`), never linked on GitHub.
IMAGES = re.compile(r"docs/img/[^/]+\.(?:svg|png|webp)")

# Optional local deny-list, git-ignored: one word per line, `#` starts a
# comment. A page that holds one of the words is left out of the site. Without
# the file the check is skipped.
DENY_FILE = REPO / "tool/site/denied-words.local"

# The generated page of the ADR section: `docs/adr/` links land here.
ADR_INDEX = "adr/index.md"

# The guide of an official link without a guide of its own name.
CATEGORY_GUIDES = {
    "File stores": "docs/filestores.md",
    "History sync": "docs/adr/0026-history-sync-to-external-databases.md",
    "Messaging": "docs/messenger.md",
}

LATEST_ADRS = 10
LATEST_CHANGES = 6


class BuildError(Exception):
    pass


# --------------------------------------------------------------------- sources

def tracked_files() -> list[str]:
    out = subprocess.run(
        ["git", "ls-files", "-z"], cwd=REPO, check=True, capture_output=True
    ).stdout.decode()
    return [p for p in out.split("\0") if p]


def excluded_reason(path: str) -> str | None:
    if path in EXCLUDED_FILES:
        return EXCLUDED_FILES[path]
    for prefix, reason in EXCLUDED_DIRS.items():
        if path.startswith(prefix):
            return reason
    return None


def load_denied_words() -> list[re.Pattern]:
    if not DENY_FILE.is_file():
        return []
    words = []
    for line in DENY_FILE.read_text(encoding="utf-8").splitlines():
        word = line.split("#", 1)[0].strip()
        if word:
            words.append(re.compile(r"\b" + re.escape(word) + r"\b", re.I))
    return words


DENIED = load_denied_words()


def denied_word(text: str) -> bool:
    return any(p.search(text) for p in DENIED)


def site_path(repo_path: str) -> str:
    """Where a repo file lands in the book, which is the site's `/docs/`: a
    guide `docs/x.md` is `x.md` (`/docs/x.html`), an ADR is under `adr/`, the
    spec under `spec/`. A README.md becomes index.md so that mdBook's index
    preprocessor and our links agree; the two READMEs that would take the
    book's own index get names."""
    if repo_path == "README.md":
        return "overview.md"
    if repo_path == "docs/README.md":
        return "map.md"
    if repo_path.startswith("docs/"):
        repo_path = repo_path[len("docs/"):]
    head, name = posixpath.split(repo_path)
    if name == "README.md":
        return posixpath.join(head, "index.md")
    return repo_path


def first_heading(text: str, fallback: str) -> str:
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith(("```", "~~~")):
            in_fence = not in_fence
        if not in_fence and line.startswith("# "):
            return line[2:].strip()
    return fallback


def summary_title(title: str) -> str:
    return title.replace("[", "\\[").replace("]", "\\]")


# --------------------------------------------------------- security finding IDs

# Security weaknesses stay private: the IDs of review findings never reach the
# site, even for fixed ones. The IDs are read at build time from the sources
# left out on purpose: the first column of their tables headed `ID`, and their
# headings `### <ID> — …`.
FINDING_SOURCES = ("docs/adr/0031-security-review-2026-10-31.md", "docs/security/")
FINDING_ID = re.compile(r"[A-Z]+-?\d+")
# A short ID (`T3`, `S2`) is also a name of other things (Amazon S3, an S7
# timer): it counts as a finding ID only after "audit"/"review" in its clause.
FINDING_CONTEXT = re.compile(r"\b(audit|review)\b|огляд", re.I)


def finding_ids(tracked: list[str]) -> set[str]:
    ids: set[str] = set()
    for p in tracked:
        if not (p == FINDING_SOURCES[0]
                or (p.startswith(FINDING_SOURCES[1]) and p.endswith(".md"))):
            continue
        lines = (REPO / p).read_text(encoding="utf-8").splitlines()
        in_ids = False
        for i, line in enumerate(lines):
            m = re.match(r"^#{2,4}\s+([A-Z]+-?\d+)\s+[—–-]\s", line)
            if m:
                ids.add(m.group(1))
            if not line.startswith("|"):
                in_ids = False
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if (i + 1 < len(lines) and re.match(r"^\|\s*:?-", lines[i + 1])):
                in_ids = cells[0] == "ID"  # a table header
                continue
            if in_ids:
                ids.update(t for t in re.split(r"[,\s]+", cells[0])
                           if FINDING_ID.fullmatch(t))
    return ids


class Scrubber:
    """Removes finding IDs from Markdown or text, with the wrapping that only
    served them: `(review X-1)` → `(review)`, `(A, X-1)` → `(A)`, `(X-1)` → ``,
    `X-1 of the review` → `review`."""

    def __init__(self, ids: set[str]):
        self.ids = ids
        alts = "|".join(sorted((re.escape(i) for i in ids), key=len, reverse=True))
        self.token = re.compile(rf"(?<![\w-])(?:{alts})(?![\w-])(?!\.\d)") if ids else None

    def applies(self, text: str, start: int, end: int) -> bool:
        if "-" in text[start:end]:
            return True
        window = text[max(0, start - 48):start]
        window = re.split(r"[(;]|\n\s*\n", window)[-1]
        return FINDING_CONTEXT.search(window) is not None

    def find(self, text: str):
        if not self.token:
            return
        for m in self.token.finditer(text):
            if self.applies(text, m.start(), m.end()):
                yield m.start(), m.end()

    def scrub(self, text: str) -> tuple[str, int]:
        removed = 0
        pos = 0
        while True:
            hit = next((h for h in self.find(text) if h[0] >= pos), None)
            if hit is None:
                return text, removed
            s, e = hit
            before = text[:s]
            after = text[e:]
            b = re.search(r"[ \t]*\([ \t]*$", before)
            if b and re.match(r"[ \t]*\)", after):  # (X-1)
                s = b.start()
                e += re.match(r"[ \t]*\)", after).end()
            elif re.match(r"\s+of\s+the\s+", after):  # X-1 of the review
                e += re.match(r"\s+of\s+the\s+", after).end()
            elif b:  # (X-1, more
                e += re.match(r"[ \t]*,?[ \t]*", after).end()
            else:  # text X-1 / text, X-1
                lead = re.search(r"[ \t]*,?[ \t]*$", before)
                if lead and lead.start() < s and before[:lead.start()].strip():
                    s = lead.start()
                else:
                    e += re.match(r"[ \t]*,?[ \t]*", after).end()
            text = text[:s] + text[e:]
            removed += 1
            pos = s


# ---------------------------------------------------------------- link rewrite

FENCE = re.compile(r"^\s{0,3}(```+|~~~+)")
# A code span may break over a line, never over a blank line.
CODE_SPAN = re.compile(r"(`+)(?:(?!\n[ \t]*\n)[\s\S])+?\1")
# [text](target "title"); the text may hold one level of brackets.
INLINE_LINK = re.compile(
    r"(!?)\[((?:[^\[\]]|\[[^\[\]]*\])*)\]\(\s*<?([^)\s>]+)>?((?:\s+\"[^\"]*\")?)\s*\)")
REF_DEF = re.compile(r"^(\s{0,3}\[[^\]]+\]:\s*<?)(\S+?)(>?(?:[ \t]+.*)?)$", re.M)
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
# A line that is only badges: [![name](https://…/badge.svg)](https://…)
BADGE = re.compile(
    r"^(?:\[!\[[^\]]*\]\(https?://[^)\s]+\)\]\([^)\s]+\)[ \t]*)+\n(?:[ \t]*\n)?", re.M)


class Linker:
    def __init__(self, tracked: list[str], pages: dict[str, str],
                 excluded: set[str]):
        self.files = set(tracked)
        self.dirs = set()
        for p in tracked:
            d = posixpath.dirname(p)
            while d:
                self.dirs.add(d)
                d = posixpath.dirname(d)
        self.pages = pages  # repo path -> site path
        # figures: repo path -> place in the book
        self.images = {p: p[len("docs/"):] for p in tracked if IMAGES.fullmatch(p)}
        # A directory link lands on the directory's page in the book: its
        # README, or the generated ADR index for docs/adr.
        self.dir_pages = {posixpath.dirname(p): sp for p, sp in pages.items()
                          if posixpath.basename(p) == "README.md"
                          and posixpath.dirname(p)}
        self.dir_pages.setdefault("docs/adr", ADR_INDEX)
        self.excluded = excluded  # repo paths left out on purpose
        self.broken: list[tuple[str, str]] = []
        self.to_github = 0
        self.unlinked = 0
        self.scrubber = Scrubber(finding_ids(tracked))
        self.ids_removed = 0
        self.id_pages: set[str] = set()

    def is_excluded(self, path: str) -> bool:
        return (path in self.excluded or excluded_reason(path) is not None
                or excluded_reason(path + "/") is not None)

    def rewrite(self, target: str, repo_page: str, site_page: str) -> str | None:
        """The new target of a link, or None for a file left out on purpose:
        such a link becomes plain text, never a link to GitHub."""
        if SCHEME.match(target) or target.startswith("#"):
            return target
        path, sep, frag = target.partition("#")
        frag = sep + frag
        path = path.split("?", 1)[0]
        if path.startswith("/"):
            resolved = posixpath.normpath(path.lstrip("/"))
        else:
            resolved = posixpath.normpath(
                posixpath.join(posixpath.dirname(repo_page), path))
        if resolved == "." or resolved.startswith(".."):
            if resolved == ".":
                self.to_github += 1
                return GITHUB + frag
            self.broken.append((repo_page, target))
            return target
        if self.is_excluded(resolved):
            self.unlinked += 1
            return None
        page = (self.pages.get(resolved) or self.dir_pages.get(resolved)
                or self.images.get(resolved))
        if page:
            rel = posixpath.relpath(page, posixpath.dirname(site_page) or ".")
            return rel + frag
        if resolved in self.files:
            self.to_github += 1
            return BLOB + resolved + frag
        if resolved in self.dirs:
            self.to_github += 1
            return TREE + resolved + frag
        self.broken.append((repo_page, target))
        return target

    def rewrite_text(self, text: str, repo_page: str, site_page: str) -> str:
        """Rewrite the links of a Markdown text outside fenced code blocks.
        Each run of lines between fences is handled as one block, so a link
        or a code span that breaks over a line is seen whole."""
        out: list[str] = []
        block: list[str] = []
        in_fence: str | None = None

        def flush() -> None:
            if block:
                out.append(self._rewrite_block("\n".join(block),
                                               repo_page, site_page))
                block.clear()

        for line in text.split("\n"):
            m = FENCE.match(line)
            if m:
                mark = m.group(1)[0]
                if in_fence is None:
                    flush()
                    in_fence = mark
                elif in_fence == mark:
                    in_fence = None
                out.append(line)
                continue
            if in_fence:
                out.append(line)
            else:
                block.append(line)
        flush()
        return "\n".join(out)

    def _rewrite_block(self, block: str, repo_page: str, site_page: str) -> str:
        spans: list[str] = []

        def mask(m: re.Match) -> str:
            spans.append(m.group(0))
            return f"\0{len(spans) - 1}\0"

        masked = CODE_SPAN.sub(mask, block)

        def ref(m: re.Match) -> str:
            new = self.rewrite(m.group(2), repo_page, site_page)
            if new is None:  # an excluded file: the definition goes
                return ""
            return m.group(1) + new + m.group(3)

        def inline(m: re.Match) -> str:
            new = self.rewrite(m.group(3), repo_page, site_page)
            if new is None:  # an excluded file: keep the text, drop the link
                return m.group(2) if not m.group(1) else m.group(0)
            return f"{m.group(1)}[{m.group(2)}]({new}{m.group(4)})"

        masked = REF_DEF.sub(ref, masked)
        masked = INLINE_LINK.sub(inline, masked)
        masked, n = self.scrubber.scrub(masked)
        if n:
            self.ids_removed += n
            self.id_pages.add(site_page)
        return re.sub("\0(\\d+)\0", lambda m: spans[int(m.group(1))], masked)


# ------------------------------------------------------------ page furniture

# What the design's pages have and plain Markdown lacks: the section number
# above the title, a figure with its caption, and a "More:" row of the
# decisions and spec parts a section names. The sources stay plain Markdown
# that GitHub renders; this is added to the copy in the book only.

KICKER = '<p class="wy-kicker" data-kind="{kind}"><span>{number}</span> {section}</p>'
# A paragraph that is one image, and the paragraph in italics right under it.
FIGURE = re.compile(
    r"(?:\A|(?<=\n\n))(!\[[^\]\n]*\]\([^)\n]+\))[ \t]*\n"
    r"(?:[ \t]*\n\*(?![*\s])((?:(?!\n[ \t]*\n).)+?)\*[ \t]*\n)?(?=[ \t]*\n|\Z)", re.S)
MORE_LINK = re.compile(r"\]\(((?:\.\./)*(?:adr/\d{4}-|spec/)[^)#\s]+\.md)(?:#[^)\s]*)?\)")
MORE_ADR = re.compile(r"\bADRs?[  ](\d{4})(?:[–-](\d{4}))?\b")
MORE_SPEC = re.compile(r"\b[Ss]pec[  /](0\d)\b")
MORE_MAX = 8


def fenced(text: str):
    """The lines of a Markdown text with a flag: inside a fenced code block."""
    in_fence: str | None = None
    for line in text.split("\n"):
        m = FENCE.match(line)
        if m:
            mark = m.group(1)[0]
            if in_fence is None:
                in_fence = mark
            elif in_fence == mark:
                in_fence = None
            yield line, True
        else:
            yield line, in_fence is not None


def outside_fences(text: str, fn) -> str:
    """Apply `fn` to each run of lines between fenced code blocks."""
    out: list[str] = []
    block: list[str] = []
    for line, code in fenced(text):
        if code:
            if block:
                out.append(fn("\n".join(block)))
                block = []
            out.append(line)
        else:
            block.append(line)
    if block:
        out.append(fn("\n".join(block)))
    return "\n".join(out)


def figures(text: str) -> str:
    def one(m: re.Match) -> str:
        caption = (m.group(2) or "").strip()
        out = f'<figure class="wy-figure">\n\n{m.group(1)}\n\n'
        if caption:
            out += f"<figcaption>\n\n{caption}\n\n</figcaption>\n"
        return out + "</figure>\n"
    return outside_fences(text, lambda block: FIGURE.sub(one, block))


class Furniture:
    def __init__(self, pages: dict[str, str]):
        self.adrs: dict[str, str] = {}   # number -> site path
        self.specs: dict[str, str] = {}  # "01" -> site path
        self.labels: dict[str, str] = {}  # site path -> the label of a "More:" link
        for p, sp in pages.items():
            m = re.fullmatch(r"docs/adr/(\d{4})-[^/]+\.md", p)
            if m:
                self.adrs[m.group(1)] = sp
                self.labels[sp] = f"ADR {m.group(1)}"
            m = re.fullmatch(r"spec/(\d\d)-[^/]+\.md", p)
            if m:
                self.specs[m.group(1)] = sp
                self.labels[sp] = f"spec {m.group(1)}"
        if "spec/README.md" in pages:
            self.labels[pages["spec/README.md"]] = "spec"
        if "spec/CHANGELOG.md" in pages:
            self.labels[pages["spec/CHANGELOG.md"]] = "spec changelog"

    def named(self, chunk: str, site_page: str) -> list[str]:
        """The decisions and spec parts a text names, by a link or by their
        number, in the order it names them, as site paths."""
        here = posixpath.dirname(site_page) or "."
        hits: list[tuple[int, str]] = []
        text = CODE_SPAN.sub(lambda m: " " * len(m.group(0)), chunk)
        for m in MORE_LINK.finditer(text):
            hits.append((m.start(), posixpath.normpath(posixpath.join(here, m.group(1)))))
        for m in MORE_ADR.finditer(text):
            first, last = int(m.group(1)), int(m.group(2) or m.group(1))
            if last - first < 4:  # "ADR 0001–0011" names a range, not each one
                for n in range(first, last + 1):
                    hits.append((m.start(), self.adrs.get(f"{n:04d}", "")))
        for m in MORE_SPEC.finditer(text):
            hits.append((m.start(), self.specs.get(m.group(1), "")))
        seen: list[str] = []
        for _, sp in sorted(hits):
            if sp in self.labels and sp != site_page and sp not in seen:
                seen.append(sp)
        return seen

    def row(self, chunk: str, site_page: str) -> str:
        targets = self.named(chunk, site_page)[:MORE_MAX]
        if not targets:
            return ""
        here = posixpath.dirname(site_page) or "."
        links = " · ".join(f"[{self.labels[sp]}]({posixpath.relpath(sp, here)})"
                           for sp in targets)
        return f'<span class="wy-more">More:</span> {links}'

    def more(self, text: str, site_page: str, by_section: bool) -> str:
        """Add the "More:" rows: one at the end of the intro and of each `##`
        section of a guide, or one at the end of a decision or a spec part."""
        chunks: list[list[str]] = [[]]
        for line, code in fenced(text):
            if by_section and not code and line.startswith("## "):
                chunks.append([])
            chunks[-1].append(line)
        out: list[str] = []
        for lines in chunks:
            chunk = "\n".join(lines)
            prose = "\n".join(line for line, code in fenced(chunk) if not code)
            row = self.row(prose, site_page)
            if row:
                chunk = chunk.rstrip("\n") + "\n\n" + row + "\n"
            out.append(chunk)
        return "\n".join(out)

    def dress(self, text: str, site_page: str, number: int, section: str,
              kind: str) -> str:
        text = figures(text)
        if kind in ("guide", "adr", "spec"):
            text = self.more(text, site_page, by_section=kind == "guide")
        kicker = KICKER.format(kind=kind, number=f"{number:02d}", section=esc(section))
        lines = text.split("\n")
        at = next((i for i, (line, code) in enumerate(fenced(text))
                   if not code and line.startswith("# ")), 0)
        lines[at:at] = [kicker, ""]
        return "\n".join(lines)


# ------------------------------------------------------------------ landing

def md_cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ").strip()


def link_guide(link: dict, pages: dict[str, str]) -> str:
    """The page of the book that documents an official link, or ""."""
    guide = f"docs/{link.get('id', '')}.md"
    if guide not in pages:
        guide = CATEGORY_GUIDES.get(link.get("category", ""), "")
    return pages.get(guide, "")


def readme_intro(readme: str) -> tuple[str, str]:
    """First prose paragraph of the README and its status block quote."""
    paragraphs = re.split(r"\n\s*\n", readme)
    intro = ""
    status = ""
    for para in paragraphs:
        p = para.strip()
        if not p or p.startswith(("#", "[![")):
            continue
        if p.startswith(">"):
            if not status:
                status = p
            continue
        if not intro:
            intro = p
        if intro and status:
            break
    return intro, status


def adr_status(text: str) -> str:
    for line in text.splitlines()[:12]:
        m = re.match(r"^\**Status:?\**:?\s*(.*)$", line.strip())
        if m:
            rest = m.group(1)
            word = re.split(r"[\s(·.;,]", rest.strip(), maxsplit=1)[0]
            date = re.search(r"\d{4}-\d{2}-\d{2}", rest)
            return word + (f" · {date.group(0)}" if date else "")
    return ""


def changelog_entries(text: str) -> list[tuple[tuple[int, ...], str]]:
    entries: list[tuple[tuple[int, ...], str]] = []
    for line in text.splitlines():
        m = re.match(r"^- (\d+)\.(\d+)\.(\d+)\b(.*)$", line)
        if m:
            version = tuple(int(x) for x in m.group(1, 2, 3))
            entries.append((version, line[2:]))
        elif entries and line.startswith("  ") and line.strip():
            v, t = entries[-1]
            entries[-1] = (v, t + " " + line.strip())
    entries.sort(key=lambda e: e[0], reverse=True)
    return entries


def topic_page(topic: dict, linker: Linker, adrs: list[tuple[str, str, str, str]],
               pages: dict[str, str]) -> str:
    """The reading list that opens a section with no guide of its own."""
    sp = topic["page"]
    here = posixpath.dirname(sp)
    lines = [f"# {topic['title']}", "", topic["lead"], "",
             "## Decisions", "", "| ADR | Title | Status |", "|---|---|---|"]
    by_number = {number: (p, title, status) for number, p, title, status in adrs}
    for number in topic["adrs"]:
        if number not in by_number:  # left out of the site
            continue
        p, title, status = by_number[number]
        short = re.sub(r"^ADR\s+\d+\s*[—–:-]\s*", "", title)
        lines.append(f"| {number} | [{md_cell(short)}]"
                     f"({posixpath.relpath(pages[p], here)}) | {md_cell(status)} |")
    lines += ["", "## Read also", ""]
    for path, frag, name, what in topic["more"]:
        target = linker.rewrite("/" + path + frag, sp, sp)
        if target is None:
            raise BuildError(f"{sp}: {path} is left out of the site")
        lines.append(f"- [{name}]({target}): {what}.")
    lines.append("")
    return "\n".join(lines)


def landing(linker: Linker, readme: str, adrs: list[tuple[str, str, str]],
            changelog: str, official: dict, pages: dict[str, str],
            sections: list[tuple[str, list[tuple[str, str, str]]]]) -> str:
    intro, status = readme_intro(readme)
    intro = linker.rewrite_text(intro, "README.md", "index.md")
    status = linker.rewrite_text(status, "README.md", "index.md")
    lines = [
        '<p class="wy-kicker" data-kind="home">Docs</p>',
        "",
        "# WYRM documentation",
        "",
        intro,
        "",
    ]
    if status:
        lines += [status, ""]
    lines += ["## Sections", "", "| | Section | Pages |", "|---|---|---|"]
    for i, (name, entries) in enumerate(sections, 1):
        shown = [e for e in entries if e[2] != "adr"]
        cells = " · ".join(f"[{md_cell(summary_title(t))}]({sp})" for sp, t, _ in shown)
        rest = len(entries) - len(shown)
        if rest:
            cells += f" · {rest} decisions"
        lines.append(f"| {i:02d} | [{name}]({entries[0][0]}) | {cells} |")
    lines += [
        "",
        "## Where things are",
        "",
        f"- Source code: [github.com/gencto/wyrm]({GITHUB})",
        f"- Releases: [github.com/gencto/wyrm/releases]({GITHUB}/releases)",
        f"- Read next: [Overview]({pages['README.md']})"
        f" · [Documentation map]({pages['docs/README.md']})"
        f" · [Specification]({pages['spec/README.md']})",
        "",
        "## Official links",
        "",
        "Links connect devices and services to the broker. This table comes from"
        f" [`links/official.json`]({BLOB}links/official.json).",
        "",
        "| Link | Category | Summary | Forms |",
        "|---|---|---|---|",
    ]
    for link in official.get("links", []):
        title = md_cell(link.get("title", link.get("id", "")))
        guide = link_guide(link, pages)
        if guide:
            title = f"[{title}]({guide})"
        forms = ", ".join(sorted(link.get("forms", {})))
        lines.append(
            f"| {title} | {md_cell(link.get('category', ''))} |"
            f" {md_cell(link.get('summary', ''))} | {md_cell(forms)} |")
    lines += [
        "",
        "## Latest architecture decisions",
        "",
        "| ADR | Title | Status |",
        "|---|---|---|",
    ]
    for number, path, title, status_line in sorted(adrs, reverse=True)[:LATEST_ADRS]:
        short = re.sub(r"^ADR\s+\d+\s*[—–:-]\s*", "", title)
        lines.append(f"| {number} | [{md_cell(short)}]({pages[path]}) |"
                     f" {md_cell(status_line)} |")
    lines += [
        "",
        f"All decisions: [architecture decisions]({ADR_INDEX}).",
        "",
        "## Latest specification changes",
        "",
    ]
    for _, entry in changelog_entries(changelog)[:LATEST_CHANGES]:
        lines.append(f"- {linker.rewrite_text(entry, 'spec/CHANGELOG.md', 'index.md')}")
    lines += [
        "",
        f"All changes: [specification changelog]({pages['spec/CHANGELOG.md']}).",
        "",
        "---",
        "",
        "This site is built from the repository after every merge to `main`."
        " Do not edit it by hand: change `docs/`, `spec/` or `links/official.json`.",
        "",
    ]
    return "\n".join(lines)


# ------------------------------------------------------------ designed pages

PLACEHOLDER = re.compile(r"\{\{([a-z0-9_]+)\}\}")
NUMBER_WORDS = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven",
                "Eight", "Nine", "Ten", "Eleven", "Twelve"]
# The chips of the home page, in the inline style of the design.
CHIP = ('<a href="{href}" style="padding: 8px 12px; border-radius: 6px;'
        ' background: #22282D">{text}</a>')
CHIP_PLAIN = ('<span style="padding: 8px 12px; border-radius: 6px;'
              ' background: #22282D">{text}</span>')
SECTION_CHIP = ('<span style="padding: 6px 10px; border-radius: 6px;'
                ' background: #1D2226">{text}</span>')


def esc(text: str) -> str:
    return html.escape(text, quote=True)


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def repo_fact(path: str, pattern: str, what: str) -> str:
    """One fact read from a tracked file; a missing one stops the build, so a
    page never shows a number nobody can trace."""
    m = re.search(pattern, (REPO / path).read_text(encoding="utf-8"), re.M)
    if not m:
        raise BuildError(f"{path}: cannot read {what}")
    return m.group(1)


def site_facts(tracked: list[str], texts: dict[str, str],
               adrs: list[tuple[str, str, str, str]], official: dict,
               pages: dict[str, str]) -> dict[str, str]:
    """The values of the `{{name}}` placeholders, except `root`. A value is
    HTML: text from the repository is escaped here. A link into the book is
    written as `{{root}}docs/...` and filled with the page's own root."""
    zenoh = repo_fact("Cargo.toml", r'^zenoh\s*=\s*\{\s*version\s*=\s*"=?([\d.]+)"',
                      "the Zenoh version")
    version = repo_fact("Cargo.toml", r'^version\s*=\s*"([\d.]+)"',
                        "the workspace version")
    blocks = repo_fact("README.md", r"\b(\d+) block types\b",
                       "the number of block types")
    # the measured row of the Modbus link image: binary, image, idle memory
    modbus = re.search(
        r"^\| `wyrm-link-modbus` \| ([\d.]+) \| ([\d.]+) \| (\d+ MiB) \|",
        (REPO / "deploy/docker/README.md").read_text(encoding="utf-8"), re.M)
    if not modbus:
        raise BuildError("deploy/docker/README.md: cannot read the measured"
                         " row of wyrm-link-modbus")
    changes = changelog_entries(texts["spec/CHANGELOG.md"])
    if not changes or not adrs:
        raise BuildError("no spec changelog entry or no ADR to name")
    parts = sum(1 for p in tracked if re.fullmatch(r"spec/\d\d-[^/]+\.md", p))
    fixtures = sum(1 for p in tracked
                   if re.fullmatch(r"spec/fixtures/[^/]+\.cbor\.hex", p))
    crates = sum(1 for p in tracked if re.fullmatch(r"links/[^/]+/Cargo\.toml", p))
    number, _, title, _ = adrs[-1]
    short = re.sub(r"^ADR\s+\d+\s*[—–:-]\s*", "", title).rstrip(".")
    links = official.get("links", [])

    facts = {
        "version": esc(version),
        "zenoh_version": esc(zenoh),
        "zenoh_minor": esc(".".join(zenoh.split(".")[:2])),
        "block_types": esc(blocks),
        "modbus_binary_mib": esc(modbus.group(1)),
        "modbus_image_mib": esc(modbus.group(2)),
        "modbus_idle": esc(modbus.group(3)),
        "spec_version": ".".join(str(n) for n in changes[0][0]),
        "spec_parts": NUMBER_WORDS[parts] if parts < len(NUMBER_WORDS) else str(parts),
        "fixtures_count": str(fixtures),
        "adr_count": str(len(adrs)),
        "adr_latest": f"ADR {number}: {esc(short)}",
        "link_crates": str(crates),
        "links_count": str(len(links)),
        "docs_sections": "\n".join(
            SECTION_CHIP.format(text=esc(s)) for s in SECTIONS),
    }

    # the official links as chips, one placeholder per category
    by_category: dict[str, list[str]] = {}
    for link in links:
        guide = link_guide(link, pages)
        text = esc(link.get("title", link.get("id", "")))
        chip = (CHIP.format(href="{{root}}" + DOCS + "/" + esc(guide[:-3] + ".html"),
                            text=text) if guide else CHIP_PLAIN.format(text=text))
        by_category.setdefault(link.get("category", ""), []).append(chip)
    for category, chips in by_category.items():
        facts["chips_" + slug(category)] = "\n".join(chips)

    # the install page: the official links and the files of their release
    release = json.loads(RELEASE.read_text(encoding="utf-8"))
    tag = release["tag"]
    download = f"{GITHUB}/releases/download/{tag}/"
    data = {
        "version": version,
        "release": {"tag": tag, "download": download, "assets": release["assets"]},
        "hosts": official.get("hosts", []),
        "links": links,
    }
    facts.update({
        "release_tag": esc(tag),
        "release_url": esc(f"{GITHUB}/releases/tag/{tag}"),
        "release_download": esc(download),
        # JSON inside <script type="application/json">: nothing may end it early
        "install_data": json.dumps(data, ensure_ascii=False, separators=(",", ":"))
        .replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026"),
    })
    return facts


def render(template: Path, facts: dict[str, str]) -> str:
    """Fill a designed page. An unknown placeholder stops the build, and so
    does a category of official links that the home page has no place for."""
    name = template.relative_to(REPO).as_posix()
    text = template.read_text(encoding="utf-8")
    unknown = sorted(set(PLACEHOLDER.findall(text)) - set(facts))
    if unknown:
        raise BuildError(f"{name}: unknown placeholder(s): {', '.join(unknown)}")
    if template == DESIGNED["index.html"][0]:
        missing = sorted(k for k in facts
                         if k.startswith("chips_") and "{{" + k + "}}" not in text)
        if missing:
            raise BuildError(f"{name}: no place for the official links of"
                             f" {', '.join(missing)}: add the placeholder(s)")
    # twice: a generated value may hold `{{root}}`
    for _ in range(2):
        text = PLACEHOLDER.sub(lambda m: facts[m.group(1)], text)
    return text


# -------------------------------------------------------------------- build

def build() -> int:
    tracked = tracked_files()
    warnings: list[str] = []
    excluded: list[tuple[str, str]] = []

    candidates = ["README.md"]
    for p in tracked:
        if not p.endswith(".md"):
            continue
        if (re.fullmatch(r"docs/[^/]+\.md", p)
                or re.fullmatch(r"docs/adr/\d{4}-[^/]+\.md", p)
                or re.fullmatch(r"spec/[^/]+\.md", p)
                or p.startswith(("docs/superpowers/", "docs/security/"))):
            candidates.append(p)

    pages: dict[str, str] = {}
    texts: dict[str, str] = {}
    for p in candidates:
        reason = excluded_reason(p)
        if reason:
            excluded.append((p, reason))
            continue
        text = (REPO / p).read_text(encoding="utf-8")
        # A badge is an image from another host; the site loads none.
        text = BADGE.sub("", text)
        if denied_word(text):
            excluded.append((p, "holds a word of the local deny-list"))
            warnings.append(f"{p}: excluded, it holds a word of the local deny-list")
            continue
        sp = site_path(p)
        if sp in pages.values() or sp in ("index.md", "SUMMARY.md", ADR_INDEX):
            raise BuildError(f"{p}: its place in the book, {sp}, is taken")
        pages[p] = sp
        texts[p] = text

    linker = Linker(tracked, pages, {p for p, _ in excluded})

    for d in (SRC, DIST):
        if d.exists():
            shutil.rmtree(d)
        d.mkdir(parents=True)
    for root, dest_root in ((STATIC, DIST), (ASSETS, DIST / "assets")):
        for f in sorted(root.rglob("*")) if root.is_dir() else []:
            if not f.is_file() or f.name.startswith("."):
                continue
            dest = dest_root / f.relative_to(root)
            top = dest.relative_to(DIST).parts[0].rsplit(".", 1)[0]
            if top in RESERVED or top == DOCS:
                raise BuildError(f"{f.relative_to(REPO)}: site path /{top} is reserved")
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(f, dest)

    # ---- the sections: (name, [(site path, title in the menu, kind)])
    def title_of(p: str) -> str:
        return first_heading(texts[p], posixpath.basename(p))

    docs = {posixpath.basename(p)[:-3]: p for p in pages
            if re.fullmatch(r"docs/[^/]+\.md", p) and p != "docs/README.md"}
    known = {n for _, names in SECTION_GUIDES for n in names}
    extra = sorted(n for n in docs if n not in known)
    for n in extra:
        warnings.append(f"docs/{n}.md: in no section list, put in {FALLBACK_SECTION}")

    adrs = []
    for p in pages:
        m = re.fullmatch(r"docs/adr/(\d{4})-[^/]+\.md", p)
        if m:
            adrs.append((m.group(1), p, title_of(p), adr_status(texts[p])))
    adrs.sort()
    spec = {posixpath.basename(p)[:-3]: p for p in pages if p.startswith("spec/")}
    spec_order = SPEC_ORDER + sorted(n for n in spec if n not in SPEC_ORDER)
    spec_titles = {"README": "Specification overview", "CHANGELOG": "Changelog"}

    generated: dict[str, str] = {}  # site path -> Markdown the generator writes
    sections: list[tuple[str, list[tuple[str, str, str]]]] = []
    for name, names in SECTION_GUIDES:
        entries: list[tuple[str, str, str]] = []
        if name == "Overview":
            entries.append((pages["README.md"], "Overview", "guide"))
            if "docs/README.md" in pages:
                entries.append((pages["docs/README.md"], "Documentation map", "guide"))
        if name in TOPICS:
            topic = TOPICS[name]
            generated[topic["page"]] = topic_page(topic, linker, adrs, pages)
            entries.append((topic["page"], topic["title"], "topic"))
        entries += [(pages[docs[n]], title_of(docs[n]), "guide")
                    for n in names + (extra if name == FALLBACK_SECTION else [])
                    if n in docs]
        if name == "Specification":
            entries += [(pages[spec[n]], spec_titles.get(n) or title_of(spec[n]), "spec")
                        for n in spec_order if n in spec]
        if name == "Decisions":
            rows = ["# Architecture decisions", "",
                    "One file per decision, in the order they were made. The status"
                    " says whether a decision is proposed or accepted, and when.", "",
                    "| ADR | Title | Status |", "|---|---|---|"]
            for number, p, title, status_line in adrs:
                short = re.sub(r"^ADR\s+\d+\s*[—–:-]\s*", "", title)
                rel = posixpath.relpath(pages[p], posixpath.dirname(ADR_INDEX))
                rows.append(f"| {number} | [{md_cell(short)}]({rel}) |"
                            f" {md_cell(status_line)} |")
            rows.append("")
            generated[ADR_INDEX] = "\n".join(rows)
            entries.append((ADR_INDEX, "All decisions", "topic"))
            entries += [(pages[p], t, "adr") for _, p, t, _ in adrs]
        if entries:
            sections.append((name, entries))
    for sp in generated:
        if sp in pages.values():
            raise BuildError(f"{sp}: a generated page would replace a page")

    # ---- the pages, each with its section number, figures and "More:" rows
    furniture = Furniture(pages)
    place = {sp: (i, name, kind) for i, (name, entries) in enumerate(sections, 1)
             for sp, _, kind in entries}
    sources = {sp: linker.rewrite_text(texts[p], p, sp) for p, sp in pages.items()}
    sources.update(generated)
    for sp, text in sources.items():
        if sp not in place:
            raise BuildError(f"{sp}: the page is in no section")
        number, name, kind = place[sp]
        dest = SRC / sp
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(furniture.dress(text, sp, number, name, kind), encoding="utf-8")
    for p, sp in linker.images.items():
        dest = SRC / sp
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / p, dest)

    # ---- SUMMARY: the decisions fold under "All decisions" (book.toml `fold`)
    summary = ["# Summary", "", "[Docs home](index.md)"]
    for name, entries in sections:
        summary += ["", f"# {name}", ""]
        for sp, title, kind in entries:
            indent = "  " if kind == "adr" else ""
            summary.append(f"{indent}- [{summary_title(title)}]({sp})")
    summary.append("")
    (SRC / "SUMMARY.md").write_text("\n".join(summary), encoding="utf-8")

    # ---- landing page
    official = json.loads((REPO / "links/official.json").read_text(encoding="utf-8"))
    index = landing(linker, texts["README.md"], adrs,
                    texts["spec/CHANGELOG.md"], official, pages, sections)
    if denied_word(index):
        raise BuildError("the landing page holds a word of the local deny-list")
    (SRC / "index.md").write_text(index, encoding="utf-8")

    # ---- designed pages
    facts = site_facts(tracked, texts, adrs, official, pages)
    for place, (template, root) in DESIGNED.items():
        if place.split("/", 1)[0].rsplit(".", 1)[0] in RESERVED:
            raise BuildError(f"{place}: site path is reserved")
        page = render(template, dict(facts, root=root))
        if denied_word(page):
            raise BuildError(f"{place} holds a word of the local deny-list")
        dest = DIST / place
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(page, encoding="utf-8")

    # ---- stubs at the addresses the docs had at the site root
    stubs = 0
    for sp in sorted(pages.values()):
        if not sp.startswith(MOVED):
            continue
        old = sp[:-3] + ".html"
        target = f"{DOCS}/{old}"
        dest = DIST / old
        if dest.exists():
            raise BuildError(f"{old}: a redirect stub would replace a page")
        dest.parent.mkdir(parents=True, exist_ok=True)
        href = posixpath.relpath(target, posixpath.dirname(old) or ".")
        dest.write_text(STUB.format(origin=ORIGIN, target=esc(target),
                                    href=esc(href)), encoding="utf-8")
        stubs += 1

    # ---- report
    print(f"site: {len(DESIGNED)} designed pages and {stubs} redirect stubs"
          f" in {DIST.relative_to(REPO)}")
    print(f"site: {len(sources) + 1} pages in {SRC.relative_to(REPO)}"
          f" ({len(adrs)} ADRs, {len(official.get('links', []))} official links,"
          f" {linker.to_github} links to GitHub,"
          f" {linker.unlinked} links to excluded files made plain text)")
    print(f"site: removed {linker.ids_removed} security finding IDs"
          f" ({len(linker.scrubber.ids)} known) from {len(linker.id_pages)} pages")
    for p, reason in excluded:
        print(f"site: excluded {p}: {reason}")
    for w in warnings:
        print(f"site: warning: {w}", file=sys.stderr)
    if linker.broken:
        for page, target in linker.broken:
            print(f"site: broken link in {page}: {target}", file=sys.stderr)
        print(f"site: {len(linker.broken)} broken link(s)", file=sys.stderr)
        return 1
    return 0


# -------------------------------------------------------------------- check

# Tags whose `src` the browser loads with the page.
LOADS = ("img", "script", "iframe", "source", "video", "audio", "embed")


class _Page(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.links: list[str] = []
        self.loads: list[str] = []  # what the page loads: scripts, styles, media
        self.text: list[str] = []  # text outside <script>, <style> and <pre>
        self._skip = 0

    def handle_endtag(self, tag):
        if tag in ("script", "style", "pre") and self._skip:
            self._skip -= 1

    def handle_data(self, data):
        if not self._skip:
            self.text.append(data)

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "pre"):
            self._skip += 1
        for name, value in attrs:
            if value is None:
                continue
            if name in ("id", "name"):
                self.ids.add(value)
            elif (name == "href" and tag in ("a", "link")) or (
                    name == "src" and tag in LOADS):
                self.links.append(value)
                rel = dict(attrs).get("rel") or ""
                if tag in LOADS or (tag == "link" and rel != "canonical"):
                    self.loads.append(value)


def check(site: Path) -> int:
    book = site / DOCS
    for must in [site / place for place in DESIGNED] + [book / "index.html"]:
        if not must.is_file():
            print(f"site: {must} is missing (run the generator, then"
                  " `mdbook build site`)", file=sys.stderr)
            return 1
    parsed: dict[Path, _Page] = {}

    def page(path: Path) -> _Page:
        if path not in parsed:
            p = _Page()
            p.feed(path.read_text(encoding="utf-8", errors="replace"))
            parsed[path] = p
        return parsed[path]

    errors: list[str] = []
    html_files = sorted(site.rglob("*.html"))
    checked = 0
    scrubber = Scrubber(finding_ids(tracked_files()))
    for f in html_files:
        text = "".join(page(f).text)
        for s, e in scrubber.find(text):
            errors.append(f"{f.relative_to(site).as_posix()}: a security finding ID"
                          f" is on the page: …{text[max(0, s - 40):s]}…")
        where = f.relative_to(site).as_posix()
        if denied_word(f.read_text(encoding="utf-8", errors="replace")):
            errors.append(f"{where}: holds a word of the local deny-list")
        # Nothing is loaded from another host: fonts, styles, scripts and
        # images are files of the site.
        for load in page(f).loads:
            if SCHEME.match(load) or load.startswith("//"):
                errors.append(f"{where}: {load}: loaded from another host")
        if f.name == "404.html" and f.parent == site:
            for link in page(f).links:
                if not (link.startswith(("/", "#")) or SCHEME.match(link)):
                    errors.append(f"{where}: {link}: a link of the 404 page"
                                  " must start at the site root")
        for link in page(f).links:
            for base in (BLOB, TREE):
                if link.startswith(base):
                    repo_path = link[len(base):].split("#", 1)[0].rstrip("/")
                    if (excluded_reason(repo_path)
                            or excluded_reason(repo_path + "/")):
                        errors.append(f"{where}: {link}: links an excluded file")
            if SCHEME.match(link) or link.startswith("//"):
                continue
            path, _, frag = link.partition("#")
            path = path.split("?", 1)[0]
            if not path:
                target = f
            elif path.startswith("/"):
                target = site / path.lstrip("/")
            elif f.name == "404.html" and f.parent == book:
                # mdBook's own 404 page resolves its links from `site-url`
                target = book / path
            else:
                target = f.parent / path
            target = Path(posixpath.normpath(target.as_posix()))
            if target.is_dir():
                target = target / "index.html"
            checked += 1
            if not target.exists():
                errors.append(f"{where}: {link}: no such file")
                continue
            if frag and target.suffix == ".html" and frag not in page(target).ids:
                errors.append(f"{where}: {link}: no id #{frag}")
    for p, reason in list(EXCLUDED_FILES.items()):
        for out in (book / (site_path(p)[:-3] + ".html"), site / (p[:-3] + ".html")):
            if out.exists():
                errors.append(f"excluded file {p} is in the site ({reason})")
    for prefix in EXCLUDED_DIRS:
        for out in (book / site_path(prefix), book / prefix, site / prefix):
            if out != book and out.exists():
                errors.append(f"excluded directory {prefix} is in the site")
    # every page of the book says which section it is in
    for f in html_files:
        if (book in f.parents and f.name not in ("print.html", "toc.html", "404.html")
                and 'class="wy-kicker"' not in f.read_text(encoding="utf-8")):
            errors.append(f"{f.relative_to(site).as_posix()}: no section line"
                          " above the title")
    for name in RESERVED:
        if (site / name).exists() or (site / f"{name}.html").exists():
            errors.append(f"/{name} is reserved and must stay free")
    official = json.loads((REPO / "links/official.json").read_text(encoding="utf-8"))
    for where, what in (("index.html", "on the home page"),
                        (f"{DOCS}/index.html", "in the table of the docs")):
        text = (site / where).read_text(encoding="utf-8")
        for link in official.get("links", []):
            title = link.get("title", link.get("id", ""))
            if f">{html.escape(title, quote=False)}<" not in text:
                errors.append(f"{where}: official link {title!r} is not {what}")
    for place in DESIGNED:
        left = PLACEHOLDER.findall((site / place).read_text(encoding="utf-8"))
        if left:
            errors.append(f"{place}: placeholder(s) left: {', '.join(sorted(set(left)))}")
    print(f"site: checked {checked} links in {len(html_files)} HTML files")
    for e in errors:
        print(f"site: {e}", file=sys.stderr)
    if errors:
        print(f"site: {len(errors)} link error(s)", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", metavar="SITE_DIR", type=Path,
                    help="check a built site (site/dist) instead of building")
    args = ap.parse_args()
    try:
        if args.check:
            return check(args.check.resolve())
        return build()
    except BuildError as e:
        print(f"site: error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
