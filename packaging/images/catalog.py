#!/usr/bin/env python3
"""The catalog of links the board images offer (ADR 0051 §4): `catalog.json`.

    catalog.py [--official links/official.json] [--seed-dir <dir>] --out <catalog.json>

It is published beside `index.json` (the images release, the page /start/) and
read by `wyr image build --catalog` and the page's WebAssembly as
`wyrm_image::Catalog`:

    {"links": [{"id", "form", "driver"?, "file"?, "title", "category", "summary"}]}

From `links/official.json`, in its order:
  - a link with a `builtin` form is `builtin`, with that driver;
  - `scheduler`, `alarm`, `dql` and `uplink` are `service`: every `wyrmd` carries
    them, switched by their section (crates/wyrm-image: `Service`);
  - a link whose `wasm` package is a file of `--seed-dir` (the seed packages the
    images carry in /usr/share/wyrm/seed) is `seed`, with that file. The file's
    `wyrm-link.json` names the package; a file that names no official link's
    `wasm` package, two files of one package and `seed.json` are refused.
Every other link is left out: an image cannot run it without a download.
Python 3.10+, standard library only.
"""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
# The broker's own links (crates/wyrm-image/src/choices.rs, `Service`).
SERVICES = ("scheduler", "alarm", "dql", "uplink")
MANIFEST = "wyrm-link.json"


class CatalogError(Exception):
    pass


def package_name(path: Path) -> str:
    """The `name` of the package file's `wyrm-link.json`."""
    try:
        with zipfile.ZipFile(path) as z:
            manifest = json.loads(z.read(MANIFEST))
    except (OSError, KeyError, zipfile.BadZipFile, ValueError) as e:
        raise CatalogError(f"{path.name}: no package ({MANIFEST} cannot be read: {e})") from e
    name = manifest.get("name") if isinstance(manifest, dict) else None
    if not isinstance(name, str) or not name:
        raise CatalogError(f"{path.name}: {MANIFEST} names no package")
    return name


def seeds(seed_dir: Path | None) -> dict[str, str]:
    """Package name -> file name of the seed directory."""
    out: dict[str, str] = {}
    if seed_dir is None:
        return out
    for f in sorted(seed_dir.iterdir()):
        if f.name.startswith("."):
            continue
        if f.name == "seed.json":
            raise CatalogError("seed.json: the images carry packages only")
        if f.is_symlink() or not f.is_file():
            raise CatalogError(f"{f.name}: not a plain file")
        name = package_name(f)
        if name in out:
            raise CatalogError(f"{f.name}: package {name} is also {out[name]}")
        out[name] = f.name
    return out


def catalog(official: dict, seed_files: dict[str, str]) -> dict:
    links = []
    used = set()
    for link in official.get("links", []):
        lid = link["id"]
        forms = link.get("forms", {})
        row: dict[str, str] = {"id": lid}
        if lid in SERVICES:
            row["form"] = "service"
        elif "builtin" in forms:
            row["form"] = "builtin"
            row["driver"] = forms["builtin"]
        elif forms.get("wasm") in seed_files:
            row["form"] = "seed"
            row["file"] = seed_files[forms["wasm"]]
            used.add(forms["wasm"])
        else:
            continue
        for k in ("title", "category", "summary"):
            if link.get(k):
                row[k] = link[k]
        links.append(row)
    left = sorted(set(seed_files) - used)
    if left:
        raise CatalogError("seed packages that are no official link's wasm form: "
                           + ", ".join(f"{seed_files[n]} ({n})" for n in left))
    return {"links": links}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--official", type=Path, default=REPO / "links/official.json")
    ap.add_argument("--seed-dir", type=Path, help="the seed packages the images carry")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    try:
        official = json.loads(args.official.read_text(encoding="utf-8"))
        out = catalog(official, seeds(args.seed_dir))
    except (CatalogError, OSError, ValueError) as e:
        print(f"catalog: {e}", file=sys.stderr)
        return 1
    args.out.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"catalog: {len(out['links'])} links -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
