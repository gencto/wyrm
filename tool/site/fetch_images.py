#!/usr/bin/env python3
"""Copy the base images of the latest images release into the site (/start/images/).

    python3 tool/site/build.py                    # first: it deletes and rewrites site/dist
    python3 tool/site/fetch_images.py             # then: site/dist/start/images/
    mdbook build site && python3 tool/site/build.py --check site/dist

The image builder page (`/start/`, ADR 0051 §4) fetches its index, its catalog and
the base images from its own origin, so the deploy of the site carries them. This
script takes the latest release whose tag starts with `images-v` (not a draft, not a
prerelease; by publication time, since `images-v<version>-r<n>` tags do not sort as
versions) of the repository (`--repo`, default the `GITHUB_REPOSITORY` of a workflow,
else gencto/wyrm), or a directory that holds such a release's assets (`--from-dir`),
and writes into `--out` (default site/dist/start/images):

  - for each board that `packaging/images/boards.json` marks `listed: true` and the
    release's `index.json` has with a `download`: its `.img.gz` (checked against
    `download.size` and `download.sha256`) and its `<stem>.manifest` (checked against
    `manifest_sha256`; the page links it);
  - `index.json`: the release's index with those entries only. It is a filtered copy
    of the release's index, not the file the release publishes: its SHA-256 differs.
  - `catalog.json`: the release's catalog of links, as published.

`index.json` and `catalog.json` are checked against the release's `SHA256SUMS`. A
name that is no plain file name is refused before any path is made of it. The total
may not pass `--max-mib` (900): GitHub Pages publishes at most 1 GB. Any refusal
exits 1 and leaves no file of this run in `--out`. When the repository has no
`images-v` release, nothing is written and the exit is 0: the page then says that no
image is published yet.

Python 3.10+, standard library only. A token in `GH_TOKEN` or `GITHUB_TOKEN` is sent
to api.github.com only (the release list); assets are public downloads.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import urllib.request
from pathlib import Path
from typing import BinaryIO

REPO = Path(__file__).resolve().parents[2]
BOARDS = REPO / "packaging/images/boards.json"
OUT = REPO / "site/dist/start/images"
TAG = "images-v"
INDEX_FORMAT = "wyrm-images/1"
MAX_MIB = 900
# a manifest is a package list of a few KiB; anything far larger is no manifest
MANIFEST_MAX = 1024 * 1024
# index.json, catalog.json, SHA256SUMS
SMALL_MAX = 4 * 1024 * 1024
PLAIN = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.+-]*")
HEX64 = re.compile(r"[0-9a-f]{64}")
CHUNK = 1 << 20


class Refused(Exception):
    pass


def plain(name: object) -> str:
    if not isinstance(name, str) or not PLAIN.fullmatch(name) or ".." in name:
        raise Refused(f"{name!r} is no plain file name")
    return name


# ---------------------------------------------------------------- sources
class DirSource:
    """A directory holding the assets of one release (tests, a local preview)."""

    def __init__(self, path: Path):
        self.path = path

    def latest(self) -> str | None:
        return str(self.path) if (self.path / "index.json").is_file() else None

    def open(self, name: str) -> BinaryIO:
        try:
            return (self.path / plain(name)).open("rb")
        except FileNotFoundError as e:
            raise Refused(f"the release has no {name}") from e


class GitHubSource:
    """The releases of a GitHub repository."""

    API = "https://api.github.com"

    def __init__(self, repo: str, token: str | None):
        self.repo = repo
        self.token = token
        self.assets: dict[str, str] = {}

    def _get(self, url: str, api: bool):
        req = urllib.request.Request(url, headers={"User-Agent": "wyrm-site-build"})
        if api:
            req.add_header("Accept", "application/vnd.github+json")
            if self.token:
                req.add_header("Authorization", f"Bearer {self.token}")
        return urllib.request.urlopen(req, timeout=120)  # noqa: S310 (fixed https hosts)

    def latest(self) -> str | None:
        best = None
        page = 1
        while True:
            with self._get(f"{self.API}/repos/{self.repo}/releases?per_page=100&page={page}",
                           api=True) as r:
                releases = json.load(r)
            if not releases:
                break
            for rel in releases:
                if (str(rel.get("tag_name", "")).startswith(TAG) and not rel.get("draft")
                        and not rel.get("prerelease") and rel.get("published_at")):
                    if best is None or rel["published_at"] > best["published_at"]:
                        best = rel
            page += 1
        if best is None:
            return None
        for a in best.get("assets", []):
            self.assets[a["name"]] = a["browser_download_url"]
        return best["tag_name"]

    def open(self, name: str) -> BinaryIO:
        url = self.assets.get(plain(name))
        if url is None:
            raise Refused(f"the release has no {name}")
        return self._get(url, api=False)


# ---------------------------------------------------------------- copying
def copy_checked(src: BinaryIO, dest: Path, size: int | None, sha256: str, cap: int) -> int:
    """Copies `src` to `dest` through a `.part` file; refuses more than `size` (or `cap`)
    bytes, another length or another SHA-256. Returns the length."""
    h = hashlib.sha256()
    got = 0
    limit = size if size is not None else cap
    part = dest.with_name(dest.name + ".part")
    try:
        with src, part.open("wb") as f:
            while True:
                chunk = src.read(CHUNK)
                if not chunk:
                    break
                got += len(chunk)
                if got > limit:
                    raise Refused(f"{dest.name}: longer than {limit} bytes")
                h.update(chunk)
                f.write(chunk)
        if size is not None and got != size:
            raise Refused(f"{dest.name}: {got} bytes, the index says {size}")
        if h.hexdigest() != sha256:
            raise Refused(f"{dest.name}: its SHA-256 is not the one published")
        part.replace(dest)
    finally:
        part.unlink(missing_ok=True)
    return got


def read_small(source, name: str) -> bytes:
    with source.open(name) as f:
        data = f.read(SMALL_MAX + 1)
    if len(data) > SMALL_MAX:
        raise Refused(f"{name}: larger than {SMALL_MAX} bytes")
    return data


def sums(text: str) -> dict[str, str]:
    """`SHA256SUMS` (sha256sum's lines, names with or without `./`)."""
    out = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        m = re.fullmatch(r"([0-9a-f]{64}) [ *](?:\./)?(\S+)", line.strip())
        if not m:
            raise Refused(f"SHA256SUMS: a line that is no sum: {line!r}")
        out[m.group(2)] = m.group(1)
    return out


def listed_boards(boards: Path) -> set[str]:
    data = json.loads(boards.read_text(encoding="utf-8"))
    return {b["id"] for b in data.get("boards", []) if b.get("listed") is True}


def fetch(source, out: Path, boards: Path = BOARDS, max_bytes: int = MAX_MIB << 20) -> int:
    """Writes the listed images of the latest release into `out`; returns the number of
    images (0 when there is no release)."""
    release = source.latest()
    if release is None:
        print("fetch_images: no images-v* release: /start/ says that no image is published yet")
        return 0
    print(f"fetch_images: release {release}")

    published = sums(read_small(source, "SHA256SUMS").decode("utf-8"))
    small = {}
    for name in ("index.json", "catalog.json"):
        data = read_small(source, name)
        want = published.get(name)
        if want is None:
            raise Refused(f"SHA256SUMS has no line for {name}")
        if hashlib.sha256(data).hexdigest() != want:
            raise Refused(f"{name}: its SHA-256 is not the one in SHA256SUMS")
        small[name] = data
    index = json.loads(small["index.json"])
    if not isinstance(index, dict) or index.get("format") != INDEX_FORMAT:
        raise Refused(f"index.json is no {INDEX_FORMAT}")
    catalog = json.loads(small["catalog.json"])
    if not isinstance(catalog, dict) or not isinstance(catalog.get("links"), list):
        raise Refused("catalog.json has no list of links")

    listed = listed_boards(boards)
    entries = []
    for e in index.get("images", []):
        if not isinstance(e, dict) or e.get("board") not in listed or not e.get("download"):
            continue
        dl = e["download"]
        plain(dl.get("file"))
        file = plain(e.get("file"))
        if not file.endswith(".img"):
            raise Refused(f"{file}: an image file ends in .img")
        if not isinstance(dl.get("size"), int) or dl["size"] <= 0:
            raise Refused(f"{dl['file']}: no size")
        for what, sha in (("download.sha256", dl.get("sha256")),
                          ("manifest_sha256", e.get("manifest_sha256"))):
            if not isinstance(sha, str) or not HEX64.fullmatch(sha):
                raise Refused(f"{e['board']}: no {what}")
        entries.append(e)
    total = sum(len(v) for v in small.values()) + sum(
        e["download"]["size"] + MANIFEST_MAX for e in entries)
    if total > max_bytes:
        raise Refused(f"the images take {total >> 20} MiB with their manifests, more than"
                      f" {max_bytes >> 20} MiB")

    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        raise Refused(f"{out} is not empty")
    try:
        for e in entries:
            dl = e["download"]
            n = copy_checked(source.open(dl["file"]), out / dl["file"], dl["size"],
                             dl["sha256"], dl["size"])
            manifest = e["file"][: -len(".img")] + ".manifest"
            copy_checked(source.open(manifest), out / manifest, None,
                         e["manifest_sha256"], MANIFEST_MAX)
            print(f"fetch_images: {e['board']}: {dl['file']} ({n >> 20} MiB) and {manifest}")
        site_index = dict(index)
        site_index["images"] = entries
        (out / "index.json").write_text(json.dumps(site_index, indent=1) + "\n", encoding="utf-8")
        (out / "catalog.json").write_bytes(small["catalog.json"])
    except BaseException:
        shutil.rmtree(out, ignore_errors=True)
        raise
    print(f"fetch_images: {len(entries)} image(s) of listed boards in {out}")
    return len(entries)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "gencto/wyrm"))
    ap.add_argument("--from-dir", type=Path, help="a directory with a release's assets")
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--boards", type=Path, default=BOARDS)
    ap.add_argument("--max-mib", type=int, default=MAX_MIB)
    args = ap.parse_args()
    if args.from_dir:
        source = DirSource(args.from_dir)
    else:
        source = GitHubSource(args.repo, os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN"))
    try:
        fetch(source, args.out, args.boards, args.max_mib << 20)
    except (Refused, OSError, ValueError, KeyError) as e:
        print(f"fetch_images: refused: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
