#!/usr/bin/env python3
"""Build the source of the WYRM home site (mdBook) from the repository.

    python3 tool/site/build.py                 # write site/src/ from the repo
    python3 tool/site/build.py --check site/book   # check links of a built site

The repository's `docs/`, `docs/adr/` and `spec/` are the one source of truth.
This script copies the guides, ADRs and the spec into `site/src/` (generated,
git-ignored), rewrites the links that leave the book to GitHub, writes
`SUMMARY.md` and the landing page `index.md`. Only files tracked by git are
read. `--check` parses every HTML page of a built site and fails on a link to a
missing page or a missing `#id`. Python 3.10+, standard library only.
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
SRC = SITE / "src"
STATIC = SITE / "static"  # copied as is into the book root (CNAME; room for /start)
GITHUB = "https://github.com/gencto/wyrm"
BLOB = f"{GITHUB}/blob/main/"
TREE = f"{GITHUB}/tree/main/"

# Site paths the generator never writes: kept free for later pages
# (`/start`: the image builder of ADR 0051).
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

# docs/*.md by section. A new doc that is in no list lands in Guides (with a
# warning), so it never disappears from the site in silence.
GUIDES = [
    "broker", "history", "scheduler", "dql", "alarm", "uplink",
    "flow-blocks", "claude", "mcp", "agent",
]
LINKS = [
    "links", "modbus", "bacnet", "knx", "opcua", "s7", "snmp", "http", "prometheus",
    "filestores", "messenger", "telegram", "slack",
]
OPERATIONS = ["operations", "backups"]
SPEC_ORDER = ["README", "01-keyspace", "02-meta", "03-val", "04-attachment",
              "05-methods", "06-flow-def", "CHANGELOG"]

# Optional local deny-list, git-ignored: one word per line, `#` starts a
# comment. A page that holds one of the words is left out of the site. Without
# the file the check is skipped.
DENY_FILE = REPO / "tool/site/denied-words.local"

# The generated page of the ADR section: `docs/adr/` links land here.
ADR_INDEX = "docs/adr/index.md"

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
    """Where a repo file lands in the book. README.md becomes index.md so that
    mdBook's index preprocessor and our links agree."""
    if repo_path == "README.md":
        return "overview.md"
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
        page = self.pages.get(resolved) or self.dir_pages.get(resolved)
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


# ------------------------------------------------------------------ landing

def md_cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ").strip()


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


def landing(linker: Linker, readme: str, adrs: list[tuple[str, str, str]],
            changelog: str, official: dict, pages: dict[str, str]) -> str:
    intro, status = readme_intro(readme)
    intro = linker.rewrite_text(intro, "README.md", "index.md")
    status = linker.rewrite_text(status, "README.md", "index.md")
    lines = [
        "# WYRM",
        "",
        intro,
        "",
    ]
    if status:
        lines += [status, ""]
    lines += [
        f"- Source code: [github.com/gencto/wyrm]({GITHUB})",
        f"- Releases: [github.com/gencto/wyrm/releases]({GITHUB}/releases)",
        "- Read next: [Overview](overview.md) · [Documentation map](docs/index.md)"
        " · [Specification](spec/index.md)",
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
        guide = f"docs/{link.get('id', '')}.md"
        if guide not in pages:
            guide = CATEGORY_GUIDES.get(link.get("category", ""), "")
        if guide in pages:
            title = f"[{title}]({pages[guide]})"
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
        if denied_word(text):
            excluded.append((p, "holds a word of the local deny-list"))
            warnings.append(f"{p}: excluded, it holds a word of the local deny-list")
            continue
        sp = site_path(p)
        if sp.split("/", 1)[0].rsplit(".", 1)[0] in RESERVED:
            raise BuildError(f"{p}: site path {sp} is reserved")
        pages[p] = sp
        texts[p] = text

    linker = Linker(tracked, pages, {p for p, _ in excluded})

    if SRC.exists():
        shutil.rmtree(SRC)
    SRC.mkdir(parents=True)
    if STATIC.is_dir():
        for f in sorted(STATIC.rglob("*")):
            if f.is_file():
                dest = SRC / f.relative_to(STATIC)
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(f, dest)

    for p, sp in pages.items():
        dest = SRC / sp
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(linker.rewrite_text(texts[p], p, sp), encoding="utf-8")

    # ---- SUMMARY
    def entry(p: str, title: str | None = None) -> str:
        t = title or first_heading(texts[p], posixpath.basename(p))
        return f"- [{summary_title(t)}]({pages[p]})"

    docs = {posixpath.basename(p)[:-3]: p for p in pages
            if re.fullmatch(r"docs/[^/]+\.md", p) and p != "docs/README.md"}
    known = set(GUIDES) | set(LINKS) | set(OPERATIONS)
    extra = sorted(n for n in docs if n not in known)
    for n in extra:
        warnings.append(f"docs/{n}.md: in no section list, put in Guides")

    summary = ["# Summary", "", "[Home](index.md)", "", "# Start", ""]
    summary.append(entry("README.md", "Overview"))
    if "docs/README.md" in pages:
        summary.append(entry("docs/README.md", "Documentation map"))
    for part, names in (("Guides", GUIDES + extra), ("Links (connectors)", LINKS),
                        ("Operations", OPERATIONS)):
        summary += ["", f"# {part}", ""]
        summary += [entry(docs[n]) for n in names if n in docs]

    adrs = []
    for p in pages:
        m = re.fullmatch(r"docs/adr/(\d{4})-[^/]+\.md", p)
        if m:
            adrs.append((m.group(1), p, first_heading(texts[p], p),
                         adr_status(texts[p])))
    adrs.sort()
    summary += ["", "# Architecture decisions", ""]
    if ADR_INDEX not in pages.values():
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
        (SRC / ADR_INDEX).write_text("\n".join(rows), encoding="utf-8")
        summary.append(f"- [All decisions]({ADR_INDEX})")
    summary += [entry(p, t) for _, p, t, _ in adrs]

    spec = {posixpath.basename(p)[:-3]: p for p in pages if p.startswith("spec/")}
    order = SPEC_ORDER + sorted(n for n in spec if n not in SPEC_ORDER)
    summary += ["", "# Specification", ""]
    for n in order:
        if n in spec:
            title = {"README": "Specification overview",
                     "CHANGELOG": "Changelog"}.get(n)
            summary.append(entry(spec[n], title))
    summary.append("")
    (SRC / "SUMMARY.md").write_text("\n".join(summary), encoding="utf-8")

    # ---- landing page
    official = json.loads((REPO / "links/official.json").read_text(encoding="utf-8"))
    index = landing(linker, texts["README.md"], adrs,
                    texts["spec/CHANGELOG.md"], official, pages)
    if denied_word(index):
        raise BuildError("the landing page holds a word of the local deny-list")
    (SRC / "index.md").write_text(index, encoding="utf-8")

    # ---- report
    print(f"site: {len(pages) + 1} pages in {SRC.relative_to(REPO)}"
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

class _Page(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.links: list[str] = []
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
                    name == "src" and tag in ("img", "script")):
                self.links.append(value)


def check(book: Path) -> int:
    if not (book / "index.html").is_file():
        print(f"site: {book} has no index.html (build the book first)", file=sys.stderr)
        return 1
    parsed: dict[Path, _Page] = {}

    def page(path: Path) -> _Page:
        if path not in parsed:
            p = _Page()
            p.feed(path.read_text(encoding="utf-8", errors="replace"))
            parsed[path] = p
        return parsed[path]

    errors: list[str] = []
    html_files = sorted(book.rglob("*.html"))
    checked = 0
    scrubber = Scrubber(finding_ids(tracked_files()))
    for f in html_files:
        text = "".join(page(f).text)
        for s, e in scrubber.find(text):
            errors.append(f"{f.relative_to(book).as_posix()}: a security finding ID"
                          f" is on the page: …{text[max(0, s - 40):s]}…")
        for link in page(f).links:
            for base in (BLOB, TREE):
                if link.startswith(base):
                    repo_path = link[len(base):].split("#", 1)[0].rstrip("/")
                    if (excluded_reason(repo_path)
                            or excluded_reason(repo_path + "/")):
                        errors.append(f"{f.relative_to(book).as_posix()}:"
                                      f" {link}: links an excluded file")
            if SCHEME.match(link) or link.startswith("//"):
                continue
            path, _, frag = link.partition("#")
            path = path.split("?", 1)[0]
            if not path:
                target = f
            elif path.startswith("/"):
                target = book / path.lstrip("/")
            else:
                target = f.parent / path
            target = Path(posixpath.normpath(target.as_posix()))
            if target.is_dir():
                target = target / "index.html"
            checked += 1
            where = f.relative_to(book).as_posix()
            if not target.exists():
                errors.append(f"{where}: {link}: no such file")
                continue
            if frag and target.suffix == ".html" and frag not in page(target).ids:
                errors.append(f"{where}: {link}: no id #{frag}")
    for p, reason in list(EXCLUDED_FILES.items()):
        out = book / (site_path(p)[:-3] + ".html")
        if out.exists():
            errors.append(f"excluded file {p} is in the site ({reason})")
    for prefix in EXCLUDED_DIRS:
        if (book / prefix).exists():
            errors.append(f"excluded directory {prefix} is in the site")
    official = json.loads((REPO / "links/official.json").read_text(encoding="utf-8"))
    landing_html = (book / "index.html").read_text(encoding="utf-8")
    for link in official.get("links", []):
        title = link.get("title", link.get("id", ""))
        if f">{html.escape(title, quote=False)}<" not in landing_html:
            errors.append(f"index.html: official link {title!r} is not in the table")
    print(f"site: checked {checked} links in {len(html_files)} HTML files")
    for e in errors:
        print(f"site: {e}", file=sys.stderr)
    if errors:
        print(f"site: {len(errors)} link error(s)", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", metavar="BOOK_DIR", type=Path,
                    help="check the links of a built site instead of building")
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
