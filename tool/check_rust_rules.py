#!/usr/bin/env python3
"""Count what docs/rust-rules.md forbids, per file, against a baseline.

A count may only go down, and a file that is not in the baseline starts at
zero. A count that went down must be written down at once (`--lower`): the
check fails on a count above and on a count below its baseline, so a fixed
hit cannot be spent again by the next change. Two kinds of rules:

* patterns C1..C12, read from the source (non-test code: `tests/`,
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


TEST_CFG = re.compile(r"#\[cfg\((?:test|all\((?:[^()]|\([^()]*\))*\btest\b(?:[^()]|\([^()]*\))*\))\)\]")
ITEM_KW = re.compile(
    r"\s*(?:#\[[^\]]*\]\s*)*(?:pub(?:\([^)]*\))?\s+)?"
    r"(?:fn|mod|impl|struct|enum|trait|use|const|static|type|async|unsafe|extern|macro_rules!)\b"
)


def test_spans(masked: str) -> list[tuple[int, int]]:
    """Offsets of `#[cfg(test)]` (and `#[cfg(all(test, …))]`) items: from the
    attribute to the item's closing brace or semicolon. An item (`fn`, `mod`,
    `impl`, …) runs to its own end whatever commas its signature holds; a
    field, arm or statement ends at the `,`/`;` that ends it, never past the
    enclosing `}`."""
    spans = []
    for m in TEST_CFG.finditer(masked):
        j = m.end()
        item = ITEM_KW.match(masked, j) is not None
        depth = 0
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
            elif depth == 0 and (ch == ";" or (ch == "," and not item)):
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


# A marker's reason must say something: at least this many characters.
MIN_REASON = 12
MARKER = re.compile(r"//\s*rust-rules:\s*allow\(([^)]*)\)\s*(.*)$")


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
        self.code_lines = self.code.split("\n")
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
        for ln in (line, line - 1):
            if 1 <= ln <= len(self.lines):
                m = MARKER.search(self.lines[ln - 1])
                if (
                    m
                    and rule in [r.strip() for r in m.group(1).split(",")]
                    and len(m.group(2).strip()) >= MIN_REASON
                ):
                    return True
        return False

    def hits(self, rule: str, offsets) -> list[int]:
        """The lines of `offsets`, without the ones a marker allows."""
        lines = (self.line_of(o) for o in sorted(set(offsets)))
        return [ln for ln in lines if not self.allowed(ln, rule)]


# ---------- the pattern rules ----------

INT = r"(?:u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|i128|isize)"
NARROW = {"u8", "u16", "u32", "i8", "i16", "i32"}
FLOATY = re.compile(r"as_f64|as_f32|\bf64\b|\bf32\b|Float\(|\.round\(\)|\.floor\(\)|\.ceil\(\)|\.trunc\(\)")


def c1(s: Source) -> list[int]:
    """An integer cast that can lose or widen silently: `as u8/u16/u32/i8/i16/i32`, `as _`
    (the target is whatever the compiler infers), and any `as <int>` within six lines after
    a float (`as_f64`, `f64`, `Float(`, `.round()`…). The code tables are exempt."""
    if s.path == "crates/wyrm-core/src/wire.rs":
        return []
    hits = []
    floaty = [i + 1 for i, line in enumerate(s.masked_lines) if FLOATY.search(line)]
    for m in re.finditer(rf"\bas\s+({INT}|_)(?![\w:])", s.masked):
        ln = s.line_of(m.start())
        if m.group(1) in NARROW or m.group(1) == "_" or any(0 <= ln - f <= 6 for f in floaty):
            hits.append(m.start())
    return s.hits("C1", hits)


NAME_CMP = r"\.name\(\)\s*(?:==|!=|\.eq\()|(?:==|!=)\s*[\w.*&()]+\.name\(\)|\bname\(\s*\*?\w+\s*\)\s*(?:==|!=)"
NAME_ARM = re.compile(r'"[\w.:-]+"\s*(?:\|\s*"[\w.:-]+"\s*)*=>\s*(?:Some\(|Ok\()?\s*(?:Self|[A-Z]\w*)::[A-Z]\w*\b(?!\s*\()')


def c2(s: Source) -> list[int]:
    """A name looked up by hand: any `.name() == s` / `.name().eq(s)` / `name(*x) == s`
    comparison (in `find`, `position`, `filter`, `any`, …), and a `match` whose string arms
    give enum variants (`"read" => Perm::Read`), counted once per `match`. A type's own
    lookup counts too: a set is named once, by `wire_enum!`. The macro itself is exempt."""
    if s.path == "crates/wyrm-core/src/wire.rs":
        return []
    hits = [m.start() for m in re.finditer(NAME_CMP, s.masked)]
    seen_match = set()
    for m in NAME_ARM.finditer(s.code):
        # the arm's `match`: the last `match` keyword before it
        k = s.masked.rfind("match ", 0, m.start())
        if k not in seen_match:
            seen_match.add(k)
            hits.append(m.start())
    return s.hits("C2", hits)


STRINGY = (
    r"(?:Option<\s*)?(?:std::string::String|String|Box<\s*str\s*>|&\s*(?:'\w+\s+)?str|"
    r"(?:std::borrow::)?Cow<[^>]*str\s*>)(?:\s*>)?"
)
FIELD = re.compile(rf"^\s*(?:pub(?:\([^)]*\))?\s+)?([a-z_][a-z0-9_]*)\s*:\s*{STRINGY}\s*(?:,|$)")
ALTS = re.compile(
    r"`[\w.-]+`\s*(?:,|\||/|\bor\b)\s*`[\w.-]+`"
    r"|`[\w-]+(?:\s*\|\s*[\w-]+)+`"
    r'|"[\w.-]+"\s*(?:,|\||/|\bor\b)\s*"[\w.-]+"'
    r"|\b(?:one of|either)\b"
    r"|\b[a-z_]+, [a-z_]+(?:, [a-z_]+)*,? or [a-z_]+\b"
)


def doc_above(s: Source, i: int) -> str:
    doc, j = [], i - 1
    while j >= 0 and (s.lines[j].strip().startswith("///") or s.lines[j].strip().startswith("#[")):
        if s.lines[j].strip().startswith("///"):
            doc.append(s.lines[j])
        j -= 1
    return " ".join(doc)


# A struct literal's field (or an assignment to one) filled from an enum's `name()`:
# `mode: def.mode.name().to_owned()`, `.into()`, `.to_string()`, `String::from(x.name())`.
NAME_FILL = re.compile(
    r"(?:(?<![\w.:])(\w+)\s*:(?!:)|\.(\w+)\s*=(?!=))\s*"
    r"(?:String::from\(\s*)?[\w.:()&*]*?\.name\(\)\s*"
    r"(?:\.\s*(?:to_owned|to_string|into)\(\)|\))"
)

# Per crate: `(struct, field)` pairs filled from an enum's `name()` anywhere in the crate,
# filled by `measure_patterns` before the rules run (C3 counts the field's declaration).
CRATE_NAME_FIELDS: dict[str, set[tuple[str, str]]] = {}


def owner_of(code: str, at: int) -> str | None:
    """The type whose literal holds the field at `at` (`LinkInfo { … mode: … }`), `Self`
    resolved to its `impl`; `None` when no type literal encloses it."""
    depth, j = 0, at
    while j > 0:
        j -= 1
        ch = code[j]
        if ch == "}":
            depth += 1
        elif ch == "{":
            if depth == 0:
                m = re.search(r"([A-Za-z_]\w*)\s*$", code[max(0, j - 80) : j])
                if not m or not m.group(1)[0].isupper():
                    return None
                name = m.group(1)
                if name == "Self":
                    imp = None
                    for imp in re.finditer(r"\bimpl(?:\s*<[^>]*>)?\s+(?:[\w:]+\s+for\s+)?(\w+)", code[:j]):
                        pass
                    return imp.group(1) if imp else None
                return name
            depth -= 1
    return None


def name_fields(code: str) -> set[tuple[str, str]]:
    """`(struct, field)` pairs of `code` filled from an enum's `name()`: in a literal of the
    struct, or assigned (`x.field = e.name().into()`, struct unknown: `("", field)`)."""
    out = set()
    for m in NAME_FILL.finditer(code):
        if m.group(1):
            owner = owner_of(code, m.start())
            if owner:
                out.add((owner, m.group(1)))
        else:
            out.add(("", m.group(2)))
    return out


STRUCT = re.compile(r"\bstruct\s+(\w+)\s*(?:<[^>{]*>)?\s*(?:where[^{]*)?\{")
ENUM = re.compile(r"\benum\s+\w+\s*(?:<[^>{]*>)?\s*(?:where[^{]*)?\{")


def field_bodies(code: str) -> list[tuple[str, int, int]]:
    """`(name, open, end)` of every body that holds named fields: a `struct`, and each
    brace variant of an `enum` (`Denied { op: String, … }`, named by the variant)."""
    out = [(m.group(1), m.end() - 1, block_end(code, m.end() - 1)) for m in STRUCT.finditer(code)]
    for em in ENUM.finditer(code):
        end = block_end(code, em.end() - 1)
        depth, j = 0, em.end()
        while j < end - 1:
            ch = code[j]
            if ch == "{":
                if depth == 0:
                    v = re.search(r"(\w+)\s*$", code[em.end() : j])
                    if v:
                        out.append((v.group(1), j, block_end(code, j)))
                depth += 1
            elif ch == "}":
                depth -= 1
            j += 1
    return out


def c3(s: Source) -> list[int]:
    """A text field or `fn` argument whose doc lists its values: a closed set carried as
    text (`String`, `&str`, `Box<str>`, `Cow<str>`, also inside `Option`); and a text field,
    documented or not, that the crate fills from an enum's `name()` (the set is the enum)."""
    hits = []
    filled = CRATE_NAME_FIELDS.get(crate_of(s.path), set()) | name_fields(s.masked)
    if filled:
        for name, open_at, end in field_bodies(s.masked):
            for k in range(s.line_of(open_at + 1), s.line_of(end) + 1):
                fm = FIELD.match(s.lines[k - 1]) if s.masked_lines[k - 1].strip() else None
                if fm and ((name, fm.group(1)) in filled or ("", fm.group(1)) in filled):
                    hits.append(s.starts[k - 1])
    for i, line in enumerate(s.lines):
        if not s.masked_lines[i].strip():
            continue
        if FIELD.match(line) and ALTS.search(doc_above(s, i)):
            hits.append(s.starts[i])
            continue
        fm = re.match(r"\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+\w+", line)
        if fm:
            doc = doc_above(s, i)
            sig = s.masked[s.starts[i] : s.masked.find("{", s.starts[i]) + 1 or s.starts[i] + 400]
            for arg in re.findall(rf"\b([a-z_][a-z0-9_]*)\s*:\s*{STRINGY}", sig):
                if re.search(rf"`{arg}`[^\n]*?(?:{ALTS.pattern})", doc):
                    hits.append(s.starts[i])
                    break
    return s.hits("C3", hits)


ARG_HELPERS = r"\b(?:arg|arg_str|opt_str|req_str|get_str|get_u64|get_bool|get_f64|enum_arg|text_arg|choice|uint_arg|bool_arg)\(\s*[^;)]*?\""
# The codec of `Value` and the decoder behind `#[derive(Args)]`.
DECODERS = ("crates/wyrm-core/src/value.rs", "crates/wyrm-core/src/args.rs")
C4_PATTERNS = [
    r"\bSome\(\s*&?\s*Value::(?:Str|UInt|Int|Bool|Float|Map|Array|Bytes|Null)\b",
    r"\bif\s+let\s+(?:Some\(\s*)?&?Value::(?:Str|UInt|Int|Bool|Float|Map|Array|Bytes)\(",
    r"\blet\s+(?:Some\(\s*)?&?Value::(?:Str|UInt|Int|Bool|Float|Map|Array|Bytes)\([^)]*\)\s*\)?\s*=",
    r'\.(?:get|get_mut|remove|contains_key)\(\s*&?\s*(?:"[^"\n]*"(?:\.to_\w+\(\))?|[A-Z][A-Z0-9_]+)\s*\)',
    r'\[\s*"[^"\n]*"\s*\]',
    r"\bValue::as_\w+\b",
    ARG_HELPERS,
]


def c4(s: Source) -> list[int]:
    """A field of a `Value` map read by hand outside a decoder: `Some(Value::…`, `if let
    Value::…(`, `let Value::…(..) =`, `.get/get_mut/remove/contains_key("x" | CONST)`,
    `m["x"]`, `Value::as_*`, and the argument helpers (`arg_str(&args, "x")`, …)."""
    if s.path.endswith("/decode.rs") or "/decode/" in s.path or s.path in DECODERS:
        return []
    hits = [m.start() for p in C4_PATTERNS for m in re.finditer(p, s.code)]
    return s.hits("C4", hits)


PUB_FN = re.compile(
    r"\bpub(?:\([^)]*\))?\s+(?:const\s+)?(?:async\s+)?(?:unsafe\s+)?(?:extern\s+\"C\"\s+)?fn\s+\w+"
)
TEXT_ERR = r"(?:std::string::String|String|&(?:'\w+)?str|Box<str>|(?:std::borrow::)?Cow<[^>]*str>)"
STRING_RESULT = rf"(?:(?:std|core)::result::)?Result<.*,{TEXT_ERR}>"


def signature_end(text: str, j: int) -> int:
    depth = 0
    while j < len(text):
        ch = text[j]
        if ch in "(<[":
            depth += 1
        elif ch in ")>]" and not (ch == ">" and text[j - 1] == "-"):
            depth -= 1
        elif depth <= 0 and (ch in "{;" or re.match(r"\bwhere\b", text[j:]) and not text[j - 1].isalnum()):
            break
        j += 1
    return j


# Per crate (its directory): names of type aliases that are a text error
# (`pub type Error = String;`), filled by `measure_patterns` before the rules run.
CRATE_TEXT_ERRORS: dict[str, set[str]] = {}


def crate_of(path: str) -> str:
    return path.split("/src/")[0] if "/src/" in path else path


def text_error_aliases(path: str, text: str) -> set[str]:
    out = set()
    for name, body in re.findall(r"\btype\s+(\w+)\s*=\s*([^;<]+);", mask(text)):
        if re.fullmatch(TEXT_ERR, re.sub(r"\s+", "", body)):
            out.add(name)
    return out


def c5(s: Source) -> list[int]:
    """A public `fn` (also a method of a `pub trait`) that returns `Result<_, String>` or
    another text error (`&str`, `Box<str>`, `Cow<str>`), also through an alias of this file
    (`type Out = Result<Json, String>`)."""
    aliases = [
        a
        for a, body in re.findall(r"\btype\s+(\w+)\s*(?:<[^=]*>)?\s*=\s*([^;]+);", s.masked)
        if re.fullmatch(STRING_RESULT, re.sub(r"\s+", "", body))
    ]
    # an error type of the crate that is text (`pub type Error = String;` in another file)
    errs = CRATE_TEXT_ERRORS.get(crate_of(s.path), set())
    err_alt = "".join(f"|(?:crate::|super::|\\w+::)*{e}" for e in sorted(errs))
    ret = (
        rf"(?:(?:std|core)::result::)?Result<.*,(?:{TEXT_ERR}{err_alt})>"
        + "".join(f"|{a}(?:<.*>)?" for a in aliases)
    )
    text = s.masked
    hits = []
    seen = set()
    for m in PUB_FN.finditer(text):
        seen.add(m.start())
        sig = re.sub(r"\s+", "", text[m.end() : signature_end(text, m.end())])
        if re.search(rf"->(?:{ret})$", sig):
            hits.append(m.start())
    for tm in re.finditer(r"\bpub(?:\([^)]*\))?\s+trait\s+\w+[^{]*\{", text):
        depth, j = 1, tm.end()
        while j < len(text) and depth:
            depth += {"{": 1, "}": -1}.get(text[j], 0)
            j += 1
        for fm in re.finditer(r"\bfn\s+\w+", text[tm.end() : j]):
            at = tm.end() + fm.start()
            if at in seen:
                continue
            e = tm.end() + fm.end()
            sig = re.sub(r"\s+", "", text[e : signature_end(text, e)])
            if re.search(rf"->(?:{ret})$", sig):
                hits.append(at)
    return s.hits("C5", hits)


ONLY_BEFORE = re.compile(r"\bonly\(\s*$")


def c6(s: Source) -> list[int]:
    """A closed set written as strings: an inline `["a", "b", …]` (with or without `&`,
    also `vec![…]`; but the key list of `Fields::only(&[…])`), `matches!(x, "a" | "b")`,
    `x == "a" || x == "b"`, and a `const`/`static` table of `&str` (also of tuples; not a
    trait's declaration of one, which holds no value). The bodies of the `name_enum!` and `wire_enum!` macros are exempt (only them, not the rest
    of their files): their `NAMES` is the one declaration of a set."""
    hits = []
    inline = r'(?:vec!)?&?\[\s*"[^"\n]*"(?:\s*,\s*"[^"\n]*")+\s*,?\s*\]'
    for m in re.finditer(inline, s.code):
        if not ONLY_BEFORE.search(s.code[max(0, m.start() - 40) : m.start()]):
            hits.append(m.start())
    hits += [m.start() for m in re.finditer(r'matches!\([^,]*,\s*"[^"\n]*"\s*\|\s*"', s.code)]
    hits += [m.start() for m in re.finditer(r'==\s*"[^"\n]*"\s*\|\|\s*[\w.]+\s*==\s*"', s.code)]
    consts = (
        r"\b(?:const|static)\s+[A-Z_][A-Z0-9_]*\s*:\s*(?:&\s*(?:'static\s+)?)?\[\s*"
        r"(?:&\s*(?:'static\s+)?str\b|\(\s*&\s*(?:'static\s+)?str\b)"
    )
    # a table holds values: an associated const's declaration (`const NAMES: &[&str];`
    # in a trait) writes none
    hits += [
        m.start()
        for m in re.finditer(consts, s.masked)
        if not re.match(r"[^=]*?\]\s*;", s.masked[m.end() :])
    ]
    spans = SET_MACROS.get(s.path)
    if spans:
        bodies = macro_bodies(s.masked, spans)
        hits = [h for h in hits if not any(a <= h < b for a, b in bodies)]
    return s.hits("C6", hits)


# The macros whose body declares a set's names (exempt from C6), by file.
SET_MACROS = {
    "crates/wyrm-core/src/named.rs": ("name_enum",),
    "crates/wyrm-core/src/wire.rs": ("wire_enum",),
}


def macro_bodies(text: str, names) -> list[tuple[int, int]]:
    """The spans of `macro_rules! <name> { … }` for each of `names` in `text`."""
    out = []
    for name in names:
        m = re.search(rf"macro_rules!\s*{name}\s*\{{", text)
        if not m:
            continue
        depth, j = 1, m.end()
        while j < len(text) and depth:
            depth += {"{": 1, "}": -1}.get(text[j], 0)
            j += 1
        out.append((m.start(), j))
    return out


def c7(s: Source) -> list[int]:
    """A selector, key or URL query written from values: a `format!`/`write!`/`writeln!`
    string (also raw) with `?x={…}`, `&x={…}`, `;x={…}`, `?{p}={…}` or `history={…}`, and a
    text piece that ends a parameter for a value to follow (`"&x="`, `"?x="` in a
    `push_str`, a `concat`, …)."""
    hits = []
    fmt = r'\b(?:format|write|writeln|format_args)!\(\s*(?:[\w.&*]+\s*,\s*)?r?#*"((?:[^"\\]|\\.)*)"'
    for m in re.finditer(fmt, s.code):
        if re.search(r"(?:[?&;][\w.{}]*=|\bhistory=)[^\"]*\{", m.group(1)):
            hits.append(m.start())
    hits += [m.start() for m in re.finditer(r'"[^"\n]*[?&;][\w.]+="', s.code)]
    return s.hits("C7", hits)


# The calls whose `Result` must never be dropped (docs/rust-rules.md rule 10): randomness,
# store writes, sealing, file modes and the secret store. Kept here, by name; `probe()` checks
# at every run that each one is caught when its result is dropped, so a name added here is
# known to work. A new security or persistence call that returns `Result` goes in this list.
PERSIST_CALLS = [
    r"getrandom::\w+",  # an RNG fill
    r"\.fill\(",  # SecureRandom::fill
    r"\.apply\(",  # a store's op
    r"\.save\(",
    r"\.persist\(",
    r"\.sync_all\(",
    r"\.sync_data\(",
    r"\.flush\(",
    r"\brename\(",
    r"\.write_all\(",
    r"\bfs::write\(",
    r"\.commit\(",
    r"\bset_permissions\(",  # a private directory or file mode
    r"\bwrite_private\(",
    r"\bwrite_file\(",  # the OPC UA store's and `PrivateDir`'s writes
    r"\bprivate_dir\(",
    r"\bseal(?:_aad|_stream|_bytes|_in_place\w*)?\(",  # sealing (an RNG nonce inside)
    # the secret store, under any receiver: its own method names, and `set`/`remove` on a
    # receiver named for secrets (`secrets.`, `link_secrets.`, `self.ctl.secrets.`)
    r"\.(?:drop_link|replace_stashed|unstash)\(",
    r"\b\w*secrets?\w*\s*\.\s*(?:set|remove)\(",
    # files and directories that hold state: a key, a certificate, a role or update
    # marker, a backup, a package. A scratch file or directory is removed through
    # `wyrm_core::files::discard` (`discard_dir`), which logs what stays instead of dropping it.
    r"\bremove_file\(",
    r"\bremove_dir_all\(",
    r"\bcreate_dir_all\(",
    r"\bremove_any\(",  # wyrm-admin `nofollow`: a file or a directory, by its own name
    r"\bremove_dir\(",  # a directory, when empty (`files::discard_empty_dir` for scratch)
    # a portable app's store (`Host::store_put`): a lost cursor repeats work
    r"\.store_put\(",
]
PERSIST = "(?:" + "|".join(PERSIST_CALLS) + ")"


def c8(s: Source) -> list[int]:
    """A dropped security or persistence result (RNG fill, store `apply`, `save`, `persist`,
    `sync_all`, `flush`, `rename`, `write_all`, …): `let _ =`, `let _x =`, `let _: T =`,
    `_ =`, `drop(…)`, `….ok();` (also after `.await`), `if ….is_err() {}`, and
    `.unwrap_or_default()` on it; and an encode that turns its error into empty bytes
    (`to_vec(..).unwrap_or_default()` / `.ok()`: use `codec::encode_to_vec`)."""
    m_ = s.masked
    pats = [
        rf"\blet\s+_\w*\s*(?::[^=;]*)?=[^;]*?{PERSIST}",
        # `_ = …;` (not a `select!` arm `_ = fut => …`)
        rf"(?<![\w.=!<>])_\s*=(?![=>])(?:(?!=>)[^;])*?{PERSIST}",
        rf"(?<!fn )\bdrop\([^;]*?{PERSIST}",
        rf"{PERSIST}[^;]*?\)(?:\.await)?\s*\.ok\(\)\s*;",
        rf"\bif\s+[^{{;]*?{PERSIST}[^{{;]*\.is_err\(\)\s*\{{\s*\}}",
        rf"{PERSIST}[^;]*?\)(?:\.await)?\s*\.unwrap_or_default\(\)",
        # the error read as a plain answer: `.unwrap_or(false)`, `.unwrap_or(0)`, …
        rf"{PERSIST}[^;]*?\)(?:\.await)?\s*\.unwrap_or\(\s*(?:false|true|0|None|\(\))\s*\)",
        # the result read as a flag: `let ok = call().is_ok();`, `.ok().is_some()`,
        # `matches!(call(), Ok(_))`
        rf"\blet\s+\w+\s*(?::\s*bool\s*)?=[^;]*?{PERSIST}[^;]*?\)(?:\.await)?\s*\.is_ok\(\)\s*;",
        rf"{PERSIST}[^;]*?\)(?:\.await)?\s*\.ok\(\)\s*\.is_some\(\)",
        rf"\bmatches!\(\s*[^;]*?{PERSIST}[^;]*?,\s*Ok\(",
        # the error mapped to a value: `.unwrap_or_else(|_| …)`
        rf"{PERSIST}[^;]*?\)(?:\.await)?\s*\.unwrap_or_else\(\s*\|\s*_\w*\s*\|",
        r"\bto_vec\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)\s*\.\s*(?:unwrap_or_default\(\)|ok\(\))",
    ]
    # a form ends within the block it starts in: `[^;]*?` must not run past the `}` of a
    # function whose last expression has no `;` and into the next one
    hits = [m.start() for p in pats for m in re.finditer(p, m_) if stays_in_block(m.group(0))]
    hits += c8_blocks(m_)
    # one hit per line, however many of the forms above match it
    return sorted(set(s.hits("C8", hits)))


def stays_in_block(span: str) -> bool:
    """`span` closes no `}` it did not open: it does not leave the block it starts in."""
    depth = 0
    for ch in span:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth < 0:
                return False
    return True


def block_end(text: str, open_at: int) -> int:
    """The offset after the `}` that closes the `{` at `open_at` (or the end of text)."""
    depth, j = 0, open_at
    while j < len(text):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return j


IF_OK = re.compile(r"\bif\s+(let\s+Ok\b[^{;]*|[^{;]*\.is_ok\(\)\s*)\{")
MATCH = re.compile(r"\bmatch\s+([^{;]*)\{")
# an `Err` arm that does nothing with the error: `{}`, `()`, `continue`, `break`, `None`,
# or a `return` of nothing, `None` or `Ok(..)`
ERR_NOTHING = re.compile(
    r"\bErr\(\s*_\w*\s*\)\s*=>\s*(?:\{\s*\}|\(\s*\)|continue\b|break\b|None\b"
    r"|return\s*(?:[;,}]|None\b|Ok\())"
)


def c8_blocks(text: str) -> list[int]:
    """The forms of C8 that need the extent of a block: `if let Ok(..) = call() { … }` and
    `if call().is_ok() { … }` with no `else` (bodies nested to any depth), and
    `match call() { …, Err(_) => {} }` (or `=> ()`)."""
    hits = []
    for m in IF_OK.finditer(text):
        if not re.search(PERSIST, m.group(1)):
            continue
        end = block_end(text, m.end() - 1)
        if not re.match(r"\s*else\b", text[end:]):
            hits.append(m.start())
    for m in MATCH.finditer(text):
        if not re.search(PERSIST, m.group(1)):
            continue
        body = text[m.end() - 1 : block_end(text, m.end() - 1)]
        if ERR_NOTHING.search(body):
            hits.append(m.start())
    return hits


# One sample call per entry of PERSIST_CALLS, in the same order.
PROBE_CALLS = [
    "getrandom::fill(&mut b)",
    "rng.fill(&mut b)",
    "store.apply(op)",
    "db.save(&x)",
    "f.persist(p)",
    "f.sync_all()",
    "f.sync_data()",
    "w.flush()",
    "std::fs::rename(a, b)",
    "f.write_all(b)",
    "std::fs::write(p, b)",
    "tx.commit()",
    "std::fs::set_permissions(dir, perms)",
    "secret::write_private(&p, b)",
    "write_file(&store.join(TOFU_OK), b\"\", false)",
    "secret::private_dir(dir)",
    "format::seal_bytes(key, path, b)",
    "store.drop_link(&peer)",
    "link_secrets.remove(id, PEER_TOKEN)",
    "std::fs::remove_file(self.peer_ca_path(site))",
    "std::fs::remove_dir_all(&dir)",
    "std::fs::create_dir_all(dir)",
    "crate::nofollow::remove_any(&pending.join(name))",
    "std::fs::remove_dir(self.rollback_dir())",
    "host.store_put(&offset_key(bot), &o.to_le_bytes())",
]
# Every way of dropping the result (C8 must see each) and of handling it (it must not).
PROBE_DROPPED = [
    "let _ = {c};",
    "let _x = {c};",
    "let _: Result<(), E> = {c};",
    "_ = {c};",
    "drop({c});",
    "{c}.ok();",
    "{c}.unwrap_or_default();",
    "if {c}.unwrap_or(false) {{ go(); }}",
    "if {c}.is_err() {{}}",
    "if let Ok(v) = {c} {{ use_it(v); }}",
    "if let Ok(v) = {c} {{ if v {{ for x in xs {{ go(x); }} }} }}",
    "if {c}.is_ok() {{ done(); }}",
    "match {c} {{ Ok(v) => use_it(v), Err(_) => {{}} }}",
    "match {c} {{ Ok(()) => go(), Err(_e) => () }}",
    "let v = {c}.unwrap_or_else(|_| fallback());",
    "for x in xs {{ match {c} {{ Ok(v) => use_it(v), Err(_) => continue }} }}",
    "let v = match {c} {{ Ok(v) => Some(v), Err(_) => None }};",
    "match {c} {{ Ok(v) => use_it(v), Err(_) => return }};",
    "let ok = {c}.is_ok();",
    "if {c}.ok().is_some() {{ done(); }} else {{ other(); }}",
    "if matches!({c}, Ok(_)) {{ done(); }} else {{ other(); }}",
]
PROBE_HANDLED = [
    "{c}?;",
    "{c}.map_err(|e| e.to_string())?;",
    "if let Err(e) = {c} {{ tracing::error!(\"{{e}}\"); }}",
    "match {c} {{ Ok(v) => v, Err(e) => return Err(e.into()) }};",
    "if let Ok(v) = {c} {{ use_it(v); }} else {{ tracing::error!(\"lost\"); }}",
    "if {c}.is_ok() {{ done(); }} else {{ tracing::error!(\"lost\"); }}",
    "match {c} {{ Ok(v) => use_it(v), Err(e) => tracing::error!(\"{{e}}\") }}",
    "let v = {c}.unwrap_or_else(|e| fail(e));",
    "match {c} {{ Ok(v) => use_it(v), Err(e) => return Err(e.into()) }};",
    # returned as the function's last expression; the next function's forms are its own
    "{c}\n}}\nfn g(w: Option<Option<u8>>) {{ let v = w.unwrap_or(None); go(v);",
]


def probe() -> list[str]:
    """C8 against samples: every call of PERSIST_CALLS caught in every dropped form, and
    never in a handled one. The list of failures (empty = the rule works)."""
    bad = []
    if len(PROBE_CALLS) != len(PERSIST_CALLS):
        return ["PROBE_CALLS needs one sample per entry of PERSIST_CALLS"]
    for pat, call in zip(PERSIST_CALLS, PROBE_CALLS):
        if not re.search(pat, call):
            bad.append(f"sample {call!r} is not a call of {pat!r}")
        for forms, want in ((PROBE_DROPPED, 1), (PROBE_HANDLED, 0)):
            for form in forms:
                code = "fn f() {\n    " + form.format(c=call) + "\n}\n"
                got = len(c8(Source("probe.rs", code)))
                if got != want:
                    bad.append(f"C8 counts {got}, not {want}: {form.format(c=call)}")
    return bad


CLOCK_HEX = r"(?:now\w*|\w*_now|unix_\w+|timestamp\w*|\w*hex\w*|\w*sha256\w*|\w*digest\w*)"


def c9(s: Source) -> list[int]:
    """A clock or hex/digest helper defined outside `wyrm-core`: a `fn` or a closure
    (`let now = || …`) named `now…`, `…_now`, `unix_…`, `timestamp…`, or holding `hex`,
    `sha256` or `digest`."""
    if s.path.startswith("crates/wyrm-core/"):
        return []
    pats = [rf"\bfn\s+{CLOCK_HEX}\b", rf"\blet\s+{CLOCK_HEX}\s*=\s*(?:move\s*)?\|"]
    return s.hits("C9", [m.start() for p in pats for m in re.finditer(p, s.masked)])


def c10(s: Source) -> list[int]:
    """A `#[param(secret)]` field whose type is not a `Secret` (a type alias of this file is
    followed to its type): a driver parameter (`Params`) or an action argument (`Args`)."""
    aliases = dict(re.findall(r"\btype\s+(\w+)\s*=\s*([^;]+);", s.masked))
    hits = []
    for m in re.finditer(r"#\[param\(([^\]]*)\)\]", s.masked):
        if not re.search(r"\bsecret\b", m.group(1)):
            continue
        f = re.compile(r"\s*(?:#\[[^\]]*\]\s*)*(?:pub(?:\([^)]*\))?\s+)?\w+\s*:\s*([^,}]+)").match(s.masked, m.end())
        if not f:
            continue
        ty = f.group(1).strip()
        for _ in range(4):
            ty = re.sub(r"\b\w+\b", lambda w: aliases.get(w.group(0), w.group(0)), ty)
        if "Secret" not in ty:
            hits.append(m.start())
    return s.hits("C10", hits)


REASON = re.compile(r'\breason\s*=\s*"((?:[^"\\]|\\.)*)"', re.S)


def allow_attrs(s: Source):
    """`#[allow(…)]`, `#![allow(…)]` and `#[expect(…)]` attributes of this file, with their
    text (the `cfg_attr` form too), outside test code."""
    for m in re.finditer(r"#!?\[(?:cfg_attr\([^\[]*?,\s*)?(?:allow|expect)\(", s.masked):
        depth, j = 0, m.start()
        while j < len(s.masked):
            if s.masked[j] == "[":
                depth += 1
            elif s.masked[j] == "]":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        yield m.start(), s.text[m.start() : j + 1]


def a1(s: Source) -> list[int]:
    """Every exception, counted so none is invisible: each `#[allow(…)]`/`#[expect(…)]` and
    each `// rust-rules: allow(Cn)` marker."""
    hits = [o for o, _ in allow_attrs(s)]
    hits += [s.starts[i] for i, line in enumerate(s.lines) if MARKER.search(line)]
    return s.hits("A1", hits)


def a2(s: Source) -> list[int]:
    """An exception without a real reason: an `allow`/`expect` with no `reason`, or one
    shorter than 12 characters, and a `rust-rules` marker whose reason is that short."""
    hits = []
    for o, attr in allow_attrs(s):
        r = REASON.search(attr)
        if not r or len(r.group(1).strip()) < MIN_REASON:
            hits.append(o)
    for i, line in enumerate(s.lines):
        mm = MARKER.search(line)
        if mm and len(mm.group(2).strip()) < MIN_REASON:
            hits.append(s.starts[i])
    return s.hits("A2", hits)


# Any mention of the helpers in code: a call, a function passed as a value
# (`.inspect_err(files::discard_dir)`), an import (`use …::files::{discard as rm}`), so no
# use of them escapes the count; a definition (`fn discard`) is not one.
DISCARD = re.compile(r"(?<!fn )\b(?:discard|discard_dir|discard_empty_dir)\b")


def a3(s: Source) -> list[int]:
    """Every removal whose error is only logged, counted like an exception so a new one shows
    in review: each mention of `wyrm_core::files::discard`, `discard_dir` and
    `discard_empty_dir` in code (a call, a function value, an import; scratch files only,
    rule 10). Their own file is not counted."""
    if s.path == "crates/wyrm-core/src/files.rs":
        return []
    return s.hits("A3", [m.start() for m in DISCARD.finditer(s.masked)])


URL_SPLIT = re.compile(
    r"(?:\b(?:split_once|rsplit_once|split|rsplit|split_terminator|rsplit_terminator|find|"
    r"rfind|contains|strip_prefix|starts_with|eq_ignore_ascii_case|match_indices|"
    r"rmatch_indices|matches|trim_start_matches|trim_matches|replace|replacen)\(\s*"
    # `splitn(2, "://")`: a count before the pattern
    r"|\b(?:splitn|rsplitn)\(\s*[^,()]+,\s*)"
    r"\"(?:[A-Za-z0-9+.-]*://|https?:?/{0,2}\")"
)


def c11(s: Source) -> list[int]:
    """A URL split by hand (review S4): `split_once("://")`, `find("://")`,
    `strip_prefix("https://")`, `starts_with("http")`, `splitn(2, "://")`,
    `match_indices("://")`, `trim_start_matches("https://")`, `replace("https://", …)`,
    … outside `wyrm_core::weburl`,
    the one parser of configured URLs (docs/rust-rules.md §11)."""
    if s.path == "crates/wyrm-core/src/weburl.rs":
        return []
    return s.hits("C11", [m.start() for m in URL_SPLIT.finditer(s.code)])


ADMIN = "crates/wyrm-admin/src/"
C12_PATTERNS = [
    # an argument reader, defined or called (not a method: `cmd.arg(…)` of a process)
    r"(?<!\.)\b(?:arg|arg_str|arg_num|arg_ms|arg_bool|arg_bytes|opt_str|req_str|get_str|get_u64|"
    r"get_bool|\w+_arg|\w+_args|from_args|accepted)\s*(?:(?:::)?<[^>()]*>)?\(",
    # the arguments map taken apart
    r"\bargs\s*\.\s*(?:get|get_mut|remove|contains_key|iter|keys|values|as_\w+|to_int)\b",
    r"\bmatch\s+[&*]*args\b",
    r"=\s*[&*]*args\s*(?:else\b|\{)",
    r"\bargs\s*\[",
    # a parameter declared by hand
    r"\bParamMeta\b",
    r"\.\s*param\(",
]


def c12(s: Source) -> list[int]:
    """In `wyrm-admin`, an action's arguments read or declared by hand: an argument reader
    (`arg(…)`, `arg_str(…)`, `int_arg(…)`, any `…_arg(…)`, `from_args(…)`), the `args` map
    taken apart (`args.get(…)`, `match args`, `let … = args else`, `args["x"]`), or a
    parameter written out (`ParamMeta`, `.param(…)`). An action's struct with
    `#[derive(Args)]` is the one declaration and the one decoder (docs/rust-rules.md §7)."""
    if not s.path.startswith(ADMIN):
        return []
    return s.hits("C12", [m.start() for p in C12_PATTERNS for m in re.finditer(p, s.masked)])


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
    "C11-url-split": c11,
    "C12-admin-arg-read": c12,
    "A1-allow": a1,
    "A2-short-reason": a2,
    "A3-scratch-discard": a3,
}

# ---------- probes ----------

# Samples each rule must count (`hit`) or leave (`miss`), checked before every run so a
# change to a pattern cannot silently stop counting what it was written for.
PROBES = [
    # C12: wyrm-admin reads and declares an action's arguments only through its struct
    ("C12", ADMIN + "x.rs", 'fn f(args: &Value) { let n = arg_str(args, "name"); }', 1),
    ("C12", ADMIN + "x.rs", 'fn f(args: &Value) { let n = int_arg::<u32>(args, "n")?; }', 1),
    ("C12", ADMIN + "x.rs", "fn arg<'a>(args: &'a Value, name: &str) -> Option<&'a Value> { None }", 1),
    ("C12", ADMIN + "x.rs", 'fn f(args: &Value) { let p = passphrase_arg(args)?; }', 1),
    ("C12", ADMIN + "x.rs", "fn f(args: &Value) { let o = UpdateOpts::from_args(args)?; }", 1),
    ("C12", ADMIN + "x.rs", "fn f(args: &Value) -> bool { accepted(args) }", 1),
    ("C12", ADMIN + "x.rs", 'fn f(args: &BTreeMap<String, Value>) { let n = args.get("name"); }', 1),
    ("C12", ADMIN + "x.rs", "fn f(args: &Value) { match args { Value::Map(m) => go(m), _ => {} } }", 1),
    ("C12", ADMIN + "x.rs", "fn f(args: &Value) { let Value::Map(m) = args else { return }; }", 1),
    ("C12", ADMIN + "x.rs", "fn f(args: &Value) { if let Value::Map(m) = &args { go(m) } }", 1),
    ("C12", ADMIN + "x.rs", 'fn f(args: &Value) { let n = &args["name"]; }', 1),
    ("C12", ADMIN + "x.rs", "fn f() -> ParamMeta { ParamMeta::of(TypeCode::String) }", 2),
    ("C12", ADMIN + "x.rs", 'fn f() -> ActionMeta { ActionMeta::new().param("n", p()) }', 1),
    # the typed way, a dispatcher that hands the map on, and a call built for another link
    (
        "C12",
        ADMIN + "x.rs",
        "#[derive(Args)]\nstruct A {\n    #[param(display = \"N\", min = 1)]\n    n: u32,\n}\n"
        "fn f(args: &Value) -> Result<A, ArgError> { A::decode(args) }\n"
        "fn g(args: &Value) { sinks::invoke(args); let mut args = BTreeMap::new(); args.insert(k, v); }\n"
        "fn h() -> ActionMeta { A::action().shown(\"n\", |p| p.placeholder(\"1\")) }",
        0,
    ),
    ("C12", "links/x/src/lib.rs", 'fn f(args: &Value) { let n = arg_str(args, "name"); }', 0),
    ("C12", ADMIN + "x.rs", '#[cfg(test)]\nmod tests { fn f(args: &Value) { arg_str(args, "n"); } }', 0),
    # C10: a secret argument is a secret type too
    ("C10", "x.rs", "#[derive(Args)]\nstruct A {\n    #[param(secret, nonempty)]\n    passphrase: Option<String>,\n}", 1),
    ("C10", "x.rs", "#[derive(Args)]\nstruct A {\n    #[param(secret, nonempty)]\n    passphrase: Option<Secret>,\n}", 0),
    ("C11", "x.rs", 'fn f(u: &str) { let (s, r) = u.split_once("://").unwrap(); }', 1),
    ("C11", "x.rs", 'fn f(u: &str) -> bool { u.strip_prefix("https://").is_some() }', 1),
    ("C11", "x.rs", 'fn f(u: &str) -> bool { u.starts_with("http") }', 1),
    ("C11", "x.rs", 'fn f(u: &str) -> Option<usize> { u.find("://") }', 1),
    ("C11", "x.rs", 'fn f(u: &str) -> String { format!("https://{u}") }', 0),
    ("C11", "x.rs", 'fn f(u: &str) { let mut p = u.splitn(2, "://"); }', 1),
    ("C11", "x.rs", 'fn f(u: &str) { let mut p = u.rsplitn(2, "://"); }', 1),
    ("C11", "x.rs", 'fn f(u: &str) { let p = u.split_terminator("://"); }', 1),
    ("C11", "x.rs", 'fn f(u: &str) { let p = u.match_indices("://"); }', 1),
    ("C11", "x.rs", 'fn f(u: &str) -> &str { u.trim_start_matches("https://") }', 1),
    ("C11", "x.rs", 'fn f(u: &str) -> &str { u.trim_start_matches("http") }', 1),
    ("C11", "x.rs", 'fn f(u: &str) -> String { u.replace("https://", "") }', 1),
    ("C11", "x.rs", 'fn f(u: &str) -> String { u.replacen("http://", "", 1) }', 1),
    ("C11", "x.rs", 'fn f(u: &str) { let p = u.splitn(2, \':\'); let q = u.split_terminator("/"); }', 0),
    ("C11", "x.rs", 'fn f(u: &str) -> String { u.replace("a", "b").trim_start_matches(\'/\').into() }', 0),
    ("C11", "crates/wyrm-core/src/weburl.rs", 'fn f(u: &str) { u.split_once("://"); }', 0),
    ("C11", "x.rs", '#[cfg(test)]\nmod tests { fn f(u: &str) { u.split_once("://"); } }', 0),
    # C3: a text field the code fills from an enum's `name()`, with no doc that lists it
    (
        "C3",
        "x.rs",
        "pub struct Info {\n    pub id: String,\n    pub mode: String,\n}\n"
        "fn f(d: &D) -> Info { Info { id: d.id.clone(), mode: d.mode.name().to_owned() } }",
        1,
    ),
    (
        "C3",
        "x.rs",
        "struct Info {\n    mode: String,\n}\nimpl Info { fn new(m: Mode) -> Self { Self { mode: m.name().into() } } }",
        1,
    ),
    (
        "C3",
        "x.rs",
        "struct Info {\n    mode: String,\n}\nfn f(i: &mut Info, m: Mode) { i.mode = String::from(m.name()); }",
        1,
    ),
    (
        "C3",
        "x.rs",
        "pub enum Event {\n    Denied {\n        user: String,\n        op: String,\n    },\n    Other(u8),\n}\n"
        "fn f(o: Op) -> Event { Event::Denied { user: String::new(), op: o.name().to_owned() } }",
        1,
    ),
    (
        "C3",
        "x.rs",
        "struct Info {\n    mode: Mode,\n    v: Value,\n    id: String,\n}\n"
        "fn f(m: Mode) -> Info { Info { mode: m, v: Value::Str(m.name().into()) } }",
        0,
    ),
    # A3: each scratch removal whose error is only logged
    (
        "A3",
        "x.rs",
        "fn f(p: &Path) {\n    wyrm_core::files::discard(p);\n    files::discard_dir(p);\n"
        "    wyrm_core::files::discard_empty_dir(p);\n}",
        3,
    ),
    ("A3", "crates/wyrm-core/src/files.rs", "pub fn discard(p: &Path) { log(p) }", 0),
    ("A3", "x.rs", "fn discard(p: &Path) {}\n// files::discard(p)", 0),
    ("A3", "x.rs", "fn f(r: io::Result<()>, p: &Path) { r.inspect_err(|_| ()); ps.iter().for_each(|p| ()); xs.for_each(wyrm_core::files::discard); }", 1),
    ("A3", "x.rs", "use wyrm_core::files::{discard_dir as rm, gone_ok};\nfn f(p: &Path) { rm(p); }", 1),
    ("C6", "x.rs", 'const NAMES: [&str; 2] = ["a", "b"];', 2),
    ("C6", "x.rs", "trait T { const NAMES: &'static [&'static str]; }", 0),
    ("C6", "x.rs", "trait T { const PAIRS: &'static [(&'static str, &'static str)]; }", 0),
    (
        "C6",
        "crates/wyrm-core/src/named.rs",
        'macro_rules! name_enum { () => { const NAMES: &[&str] = &[]; } }\nconst L: [&str; 2] = ["a", "b"];',
        2,
    ),
]


def self_test() -> list[str]:
    bad = []
    for rule, path, text, want in PROBES:
        fn = next(f for n, f in PATTERNS.items() if n.split("-")[0] == rule)
        got = len(fn(Source(path, text)))
        if got != want:
            bad.append(f"{rule} on {text!r}: {got} hits, {want} expected")
    return bad


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
    files = list(sources())
    CRATE_TEXT_ERRORS.clear()
    CRATE_NAME_FIELDS.clear()
    for path, text in files:
        CRATE_TEXT_ERRORS.setdefault(crate_of(path), set()).update(text_error_aliases(path, text))
        masked = Source(path, text).masked  # code only, tests left out
        CRATE_NAME_FIELDS.setdefault(crate_of(path), set()).update(name_fields(masked))
    for path, text in files:
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
    broken = probe() + self_test()
    if broken:
        sys.stderr.write("rust rules: a pattern no longer counts its probes\n")
        for b in broken:
            sys.stderr.write(f"  {b}\n")
        return 1
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

    over, under, lowered = [], [], {}
    for r in rules:
        b, n = base.get(r, {}), now.get(r, {})
        for f in sorted(set(b) | set(n)):
            c, was = n.get(f, 0), b.get(f, 0)
            if c > was:
                over.append(f"{r}  {f}: {c} (baseline {was})")
            elif c < was:
                under.append(f"{r}  {f}: {c} (baseline {was})")
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
    if not over and not under:
        totals = ", ".join(f"{r.split('-')[0]} {sum(now.get(r, {}).values())}" for r in rules)
        print(f"rust rules: every count is its baseline ({totals})")
        return 0
    if over:
        sys.stderr.write("rust rules: counts above the baseline (see docs/rust-rules.md)\n")
        for o in over:
            sys.stderr.write(f"  {o}\n")
    if under:
        # a fixed hit must not stay in the baseline, or the next change could spend it again
        sys.stderr.write(
            "rust rules: counts below the baseline: run `python3 tool/check_rust_rules.py --lower`"
            " and commit the baseline\n"
        )
        for u in under:
            sys.stderr.write(f"  {u}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
