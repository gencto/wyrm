#!/usr/bin/env python3
"""Count what docs/rust-rules.md forbids, per file, against a baseline.

A count may only go down, and a file that is not in the baseline starts at
zero. Two kinds of rules:

* patterns C1..C10, read from the source (non-test code: `tests/`,
  `benches/`, `examples/` and `#[cfg(test)]` items are left out);
* clippy lints that are too costly to deny at once, counted from one
  `cargo clippy --lib --bins --all-features` run in JSON.

    python3 tool/check_rust_rules.py              check (CI)
    python3 tool/check_rust_rules.py --lower      write the counts that went down
    python3 tool/check_rust_rules.py --init       write the baseline from scratch
    python3 tool/check_rust_rules.py --no-clippy  patterns only (fast; clippy counts kept)
    python3 tool/check_rust_rules.py --clippy-json FILE   read a saved clippy run
    python3 tool/check_rust_rules.py --show C7    list the hits of one pattern

A line may carry `// rust-rules: allow(C4) <why>` (or the line above it) for
one pattern hit; the reason is required. Run from the repository root.
Python 3.11+ (tomllib), standard library only.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tomllib
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "tool" / "rust_rules_baseline.json"

# Costly clippy lints, counted per file (docs/rust-rules.md, "Baselined lints").
CLIPPY = [
    "clippy::cast_possible_truncation",
    "clippy::cast_sign_loss",
    "clippy::cast_possible_wrap",
    "clippy::string_slice",
    "clippy::let_underscore_must_use",
    "clippy::map_err_ignore",
    "clippy::too_many_lines",  # threshold 150 in clippy.toml
]

# ---------- source views ----------


def mask(text: str, strings: bool = True) -> str:
    """`text` with comments blanked and, if `strings`, the insides of string
    and char literals too (newlines kept), so offsets and lines stay put."""
    out = list(text)
    i, n = 0, len(text)

    def blank(a: int, b: int, always: bool = True) -> None:
        if always or strings:
            for k in range(a, min(b, n)):
                if out[k] != "\n":
                    out[k] = " "

    def ident_before(k: int) -> bool:
        return k > 0 and (text[k - 1].isalnum() or text[k - 1] == "_")

    raw = re.compile(r'b?r(#*)"')
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif text.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if text.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif text.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            blank(i, j)
            i = j
        elif c in "br" and not ident_before(i) and raw.match(text, i):
            m = raw.match(text, i)
            close = '"' + m.group(1)
            j = text.find(close, m.end())
            j = n if j < 0 else j
            blank(m.end(), j, False)
            i = j + len(close)
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            blank(i + 1, j, False)
            i = j + 1
        elif c == "'":
            # a char literal ('x', '\n', '\u{..}') or a lifetime ('a)
            if i + 1 < n and text[i + 1] == "\\":
                j = text.find("'", i + 2)
                j = n if j < 0 else j
                blank(i + 1, j, False)
                i = j + 1
            elif i + 2 < n and text[i + 2] == "'":
                blank(i + 1, i + 2, False)
                i += 3
            else:
                i += 1
        else:
            i += 1
    return "".join(out)


def test_spans(masked: str) -> list[tuple[int, int]]:
    """Offsets of `#[cfg(test)]` items (their attribute to their closing
    brace or semicolon)."""
    spans = []
    for m in re.finditer(r"#\[cfg\(test\)\]", masked):
        j = m.end()
        depth = 0
        # to the item's closing brace, or to the `;`/`,` that ends a
        # statement, field or arm; never past the enclosing `}`
        while j < len(masked):
            ch = masked[j]
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                if depth == 0:
                    break
                depth -= 1
                if depth == 0 and ch == "}":
                    j += 1
                    break
            elif ch in ";," and depth == 0:
                j += 1
                break
            j += 1
        spans.append((m.start(), j))
    return spans


def blank_spans(text: str, spans: list[tuple[int, int]]) -> str:
    out = list(text)
    for a, b in spans:
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "
    return "".join(out)


class Source:
    def __init__(self, path: str, text: str):
        self.path = path
        self.text = text
        m = mask(text)
        spans = test_spans(m)
        self.masked = blank_spans(m, spans)  # code only, no tests
        self.code = blank_spans(mask(text, strings=False), spans)  # strings kept
        self.lines = text.split("\n")
        self.masked_lines = self.masked.split("\n")
        self.starts = [0]
        for line in self.lines:
            self.starts.append(self.starts[-1] + len(line) + 1)

    def line_of(self, offset: int) -> int:
        lo, hi = 0, len(self.starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if self.starts[mid] <= offset:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1

    def allowed(self, line: int, rule: str) -> bool:
        tag = re.compile(r"//\s*rust-rules:\s*allow\(([^)]*)\)\s*\S")
        for ln in (line, line - 1):
            if 1 <= ln <= len(self.lines):
                m = tag.search(self.lines[ln - 1])
                if m and rule in [r.strip() for r in m.group(1).split(",")]:
                    return True
        return False

    def hits(self, rule: str, offsets) -> list[int]:
        """The lines of `offsets`, without the ones a marker allows."""
        lines = (self.line_of(o) for o in offsets)
        return [ln for ln in lines if not self.allowed(ln, rule)]


# ---------- the pattern rules ----------

INT = r"(?:u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|i128|isize)"


def c1(s: Source) -> list[int]:
    """`as u8|u16|u32` outside the code tables, and any `as <int>` within
    three lines after an `as_f64` read."""
    if s.path == "crates/wyrm-core/src/wire.rs":
        return []
    hits = []
    f64_lines = [i + 1 for i, l in enumerate(s.masked_lines) if "as_f64" in l]
    for m in re.finditer(rf"\bas\s+({INT})\b", s.masked):
        ln = s.line_of(m.start())
        if m.group(1) in ("u8", "u16", "u32") or any(0 <= ln - f <= 3 for f in f64_lines):
            hits.append(m.start())
    return s.hits("C1", hits)


OWN_LOOKUP = {"from_name", "parse", "from_str", "by_name"}


def c2(s: Source) -> list[int]:
    """A name looked up by hand: `ALL…name() ==`, or any `.find(|x| x.name() == s)` /
    `name(*x) == s` search. The type's own `from_name` (or `parse`, `from_str`) is the one
    definition of its set and is not counted."""
    hits = []
    pats = [
        r"\bALL\b[^;{}]{0,240}?(?:\.name\(\)\s*==|==\s*[\w.*&]+\.name\(\))",
        r"\.find\(\s*\|[^|]*\|[^;{}]{0,160}?(?:\.name\(\)\s*==|==\s*[\w.*&]+\.name\(\)|\bname\(\s*\*?\w+\s*\)\s*==)",
    ]
    seen = set()
    for pat in pats:
        for m in re.finditer(pat, s.masked):
            ln = s.line_of(m.end())
            if ln in seen:
                continue
            fns = re.findall(r"\bfn\s+(\w+)", s.masked[: m.start()])
            if fns and fns[-1] in OWN_LOOKUP:
                continue
            seen.add(ln)
            hits.append(m.end())
    return s.hits("C2", hits)


FIELD = re.compile(r"^\s*(?:pub(?:\([^)]*\))?\s+)?[a-z_][a-z0-9_]*\s*:\s*(?:Option<\s*String\s*>|String)\s*,")
ALTS = re.compile(r"`[\w.-]+`\s*(?:,|\||/|\bor\b)\s*`[\w.-]+`|`[\w-]+(?:\s*\|\s*[\w-]+)+`")


def c3(s: Source) -> list[int]:
    """A `String` field whose doc comment lists its values: a closed set."""
    hits = []
    for i, line in enumerate(s.lines):
        if not FIELD.match(line) or not s.masked_lines[i].strip():
            continue
        doc, j = [], i - 1
        while j >= 0 and (s.lines[j].strip().startswith("///") or s.lines[j].strip().startswith("#[")):
            if s.lines[j].strip().startswith("///"):
                doc.append(s.lines[j])
            j -= 1
        if ALTS.search(" ".join(doc)):
            hits.append(s.starts[i])
    return s.hits("C3", hits)


def c4(s: Source) -> list[int]:
    """A field of a `Value` map read by hand outside a decoder."""
    if s.path.endswith("/decode.rs") or "/decode/" in s.path or s.path == "crates/wyrm-core/src/value.rs":
        return []
    pat = r'Some\(\s*Value::(?:Str|UInt|Int|Bool|Float|Map|Array|Bytes)\(|\.get\(\s*"[^"\n]*"\s*\)'
    return s.hits("C4", [m.start() for m in re.finditer(pat, s.code)])


PUB_FN = re.compile(r"\bpub(?:\([^)]*\))?\s+(?:const\s+)?(?:async\s+)?(?:unsafe\s+)?(?:extern\s+\"C\"\s+)?fn\s+\w+")


STRING_RESULT = r"(?:(?:std|core)::result::)?Result<.*,String>"


def c5(s: Source) -> list[int]:
    """A `pub fn` that returns `Result<_, String>`, also through an alias of this file
    (`type Out = Result<Json, String>`, `type Result<T> = …Result<T, String>`)."""
    aliases = [
        a
        for a, body in re.findall(r"\btype\s+(\w+)\s*(?:<[^=]*>)?\s*=\s*([^;]+);", s.masked)
        if re.fullmatch(STRING_RESULT, re.sub(r"\s+", "", body))
    ]
    ret = STRING_RESULT + "".join(f"|{a}(?:<.*>)?" for a in aliases)
    hits = []
    text = s.masked
    for m in PUB_FN.finditer(text):
        j, depth = m.end(), 0
        while j < len(text):
            ch = text[j]
            if ch in "(<[":
                depth += 1
            elif ch in ")>]":
                depth -= 1
            elif depth <= 0 and (ch in "{;" or text.startswith("where", j)):
                break
            j += 1
        sig = re.sub(r"\s+", "", text[m.end() : j])
        if re.search(rf"->(?:{ret})$", sig):
            hits.append(m.start())
    return s.hits("C5", hits)


def c6(s: Source) -> list[int]:
    """A closed set written as strings: an inline `&["a", "b", …]` (but the
    key list of `Fields::only(&[…])`), or a `const`/`static` array of `&str`."""
    inline = r'&\[\s*"[^"\n]*"(?:\s*,\s*"[^"\n]*")+\s*,?\s*\]'
    consts = r"\b(?:const|static)\s+[A-Z_][A-Z0-9_]*\s*:\s*(?:&\s*(?:'static\s+)?)?\[\s*&\s*(?:'static\s+)?str\b"
    hits = [
        m.start()
        for m in re.finditer(inline, s.code)
        if not re.search(r"\bonly\(\s*$", s.code[max(0, m.start() - 40) : m.start()])
    ]
    hits += [m.start() for m in re.finditer(consts, s.masked)]
    return s.hits("C6", hits)


def c7(s: Source) -> list[int]:
    """A selector or key parameter built with `format!` from a value
    (`?x={}`, `&x={}`, `history={}`)."""
    hits = []
    for m in re.finditer(r'format!\(\s*"((?:[^"\\]|\\.)*)"', s.code):
        if re.search(r"(?:[?&][\w.]+=|\bhistory=)[^\"]*\{", m.group(1)):
            hits.append(m.start())
    return s.hits("C7", hits)


def c8(s: Source) -> list[int]:
    """A dropped security or persistence result: `let _ =` / `_ =` of
    `getrandom::…`, `.fill(`, `store.apply(…)`, `.save(`, `.persist(`, `.sync_all(`,
    `.flush(`, or such a call ended with `.ok();`."""
    calls = r"(?:getrandom::|\.fill\(|\.apply\(|\.save\(|\.persist\(|\.sync_all\(|\.flush\()"
    pats = [
        rf"(?:\blet\s+_\s*=|(?<![\w.=!<>])_\s*=(?![=>]))[^;]*?{calls}",
        rf"(?<![=\w])\s(?:\w+::)*\w+(?:\.\w+)*{calls}[^;]*?\)\s*\.ok\(\)\s*;",
    ]
    hits = sorted({m.start() for p in pats for m in re.finditer(p, s.masked)})
    return s.hits("C8", hits)


def c9(s: Source) -> list[int]:
    """A clock or hex/digest helper defined outside `wyrm-core`: a `fn` whose name starts
    with `now_` or contains `hex` or `sha256` (`now_us`, `hex`, `wyrm_core_hex`,
    `sha256_hex`, …)."""
    if s.path.startswith("crates/wyrm-core/"):
        return []
    pat = r"\bfn\s+(?:now_\w*|\w*hex\w*|\w*sha256\w*)\b"
    return s.hits("C9", [m.start() for m in re.finditer(pat, s.masked)])


def c10(s: Source) -> list[int]:
    """A `#[param(secret)]` field whose type is not a `Secret`."""
    hits = []
    for m in re.finditer(r"#\[param\(([^\]]*)\)\]", s.masked):
        if not re.search(r"\bsecret\b", m.group(1)):
            continue
        f = re.compile(r"\s*(?:#\[[^\]]*\]\s*)*(?:pub(?:\([^)]*\))?\s+)?\w+\s*:\s*([^,}]+)").match(s.masked, m.end())
        if f and "Secret" not in f.group(1):
            hits.append(m.start())
    return s.hits("C10", hits)


PATTERNS = {
    "C1-int-cast": c1,
    "C2-name-lookup": c2,
    "C3-string-closed-set": c3,
    "C4-value-field-read": c4,
    "C5-string-error": c5,
    "C6-string-set": c6,
    "C7-selector-format": c7,
    "C8-dropped-result": c8,
    "C9-duplicate-helper": c9,
    "C10-plain-secret": c10,
}

# ---------- measuring ----------


def members() -> list[str]:
    with open(ROOT / "Cargo.toml", "rb") as f:
        return tomllib.load(f)["workspace"]["members"]


def test_module_files(path: Path, text: str) -> set[Path]:
    """Files of the `#[cfg(test)] mod x;` declarations in `path`: test code."""
    out = set()
    stem = path.parent if path.name in ("lib.rs", "main.rs", "mod.rs") else path.with_suffix("")
    for m in re.finditer(r"#\[cfg\(test\)\]\s*(?:#\[[^\]]*\]\s*)*(?:pub(?:\([^)]*\))?\s+)?mod\s+(\w+)\s*;", mask(text)):
        out |= {stem / f"{m.group(1)}.rs", stem / m.group(1) / "mod.rs"}
    return out


def sources():
    files = []
    for m in members():
        base = ROOT / m
        for dirpath, dirnames, names in os.walk(base):
            rel = Path(dirpath).relative_to(base).parts
            # test, bench and example code, and nested crates (fixtures)
            if rel and rel[0] in ("tests", "benches", "examples", "target"):
                dirnames[:] = []
                continue
            files += [Path(dirpath) / n for n in sorted(names) if n.endswith(".rs")]
    texts = {p: p.read_text(encoding="utf-8") for p in files}
    tests = set()
    for p, text in texts.items():
        tests |= test_module_files(p, text)
    for p in files:
        if p not in tests:
            yield p.relative_to(ROOT).as_posix(), texts[p]


def measure_patterns(show: str | None = None) -> dict[str, dict[str, int]]:
    out: dict[str, dict[str, int]] = {r: {} for r in PATTERNS}
    for path, text in sources():
        s = Source(path, text)
        for name, rule in PATTERNS.items():
            lines = rule(s)
            if lines:
                out[name][path] = len(lines)
            if show and name.split("-")[0] == show:
                for ln in lines:
                    print(f"{path}:{ln}: {s.lines[ln - 1].strip()}")
    return out


def clippy_json() -> list[str]:
    cmd = ["cargo", "clippy", "--workspace", "--lib", "--bins", "--all-features", "--message-format=json", "--"]
    for lint in CLIPPY:
        cmd += ["-W", lint]
    p = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode != 0:
        sys.stderr.write(p.stderr[-4000:])
        sys.exit("rust rules: the clippy run failed")
    return p.stdout.splitlines()


def measure_clippy(lines) -> dict[str, dict[str, int]]:
    out: dict[str, dict[str, int]] = {lint: {} for lint in CLIPPY}
    seen = set()
    for line in lines:
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("reason") != "compiler-message":
            continue
        m = msg["message"]
        code = (m.get("code") or {}).get("code")
        if code not in out:
            continue
        spans = [s for s in m["spans"] if s["is_primary"]]
        if not spans:
            continue
        sp = spans[0]
        # a span in a macro of another crate points there: keep ours only
        f = sp["file_name"]
        if f.startswith("/") or f.startswith(".."):
            continue
        key = (code, f, sp["line_start"], sp["column_start"])
        if key in seen:
            continue
        seen.add(key)
        out[code][f] = out[code].get(f, 0) + 1
    return out


# ---------- baseline ----------


def read_baseline() -> dict[str, dict[str, int]]:
    if not BASELINE.exists():
        return {}
    return json.loads(BASELINE.read_text())


def write(counts: dict[str, dict[str, int]]) -> None:
    rules = list(PATTERNS) + CLIPPY
    data = {r: dict(sorted((counts.get(r) or {}).items())) for r in rules}
    BASELINE.write_text(json.dumps(data, indent=2) + "\n")


def main(argv: list[str]) -> int:
    os.chdir(ROOT)
    if "--show" in argv:
        measure_patterns(argv[argv.index("--show") + 1])
        return 0
    now = measure_patterns()
    use_clippy = "--no-clippy" not in argv
    if "--clippy-json" in argv:
        now.update(measure_clippy(Path(argv[argv.index("--clippy-json") + 1]).read_text().splitlines()))
    elif use_clippy:
        now.update(measure_clippy(clippy_json()))
    base = read_baseline()
    rules = list(PATTERNS) + (CLIPPY if use_clippy or "--clippy-json" in argv else [])

    if "--init" in argv:
        if not use_clippy:
            now.update({lint: base.get(lint, {}) for lint in CLIPPY})
        write(now)
        print(f"baseline written: {BASELINE.relative_to(ROOT)}")
        return 0

    over, lowered = [], {}
    for r in rules:
        b, n = base.get(r, {}), now.get(r, {})
        for f, c in sorted(n.items()):
            if c > b.get(f, 0):
                over.append(f"{r}  {f}: {c} (baseline {b.get(f, 0)})")
        lowered[r] = {f: min(c, n[f]) for f, c in b.items() if n.get(f, 0) > 0}
    for r in set(list(PATTERNS) + CLIPPY) - set(rules):
        lowered[r] = base.get(r, {})

    if "--lower" in argv:
        if over:
            sys.stderr.write("not lowered: counts above the baseline first\n")
        else:
            write(lowered)
            print(f"baseline lowered: {BASELINE.relative_to(ROOT)}")
            return 0
    if not over:
        totals = ", ".join(f"{r.split('-')[0]} {sum(now.get(r, {}).values())}" for r in rules)
        print(f"rust rules: no count above the baseline ({totals})")
        return 0
    sys.stderr.write("rust rules: counts above the baseline (see docs/rust-rules.md)\n")
    for o in over:
        sys.stderr.write(f"  {o}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
