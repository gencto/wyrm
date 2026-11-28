#!/usr/bin/env python3
"""Test of fetch_images.py against releases written into a temporary directory.

    python3 tool/site/test_fetch_images.py

Standard library only.
"""

from __future__ import annotations

import gzip
import hashlib
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_images as fi  # noqa: E402

BOARDS = {
    "boards": [
        {"id": "rpi4", "listed": True},
        {"id": "bpi-r4", "listed": True},
        {"id": "qemu-armsr", "listed": False},
        {"id": "bpi-r4-8g", "listed": False},
    ]
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class Release:
    """The assets of an images release, as the release workflow publishes them."""

    def __init__(self, root: Path, boards=("rpi4", "qemu-armsr", "bpi-r4")):
        self.dir = root / "release"
        self.dir.mkdir()
        self.images = []
        for i, b in enumerate(boards):
            stem = f"wyrm-{b}-0.1.0-openwrt-25.12.6"
            raw = bytes([i + 1]) * (4096 + i)
            gz = gzip.compress(raw, mtime=0)
            manifest = f"base-files - 1\nwyrmd - 0.1.0 {b}\n".encode()
            (self.dir / f"{stem}.img.gz").write_bytes(gz)
            (self.dir / f"{stem}.manifest").write_bytes(manifest)
            self.images.append({
                "board": b, "file": f"{stem}.img", "size": len(raw), "sha256": sha(raw),
                "config_offset": 0, "openwrt": "25.12.6", "wyrmd": "0.1.0",
                "manifest_sha256": sha(manifest),
                "download": {"file": f"{stem}.img.gz", "size": len(gz), "sha256": sha(gz)},
            })
        self.catalog = {"links": [{"id": "modbus", "form": "builtin", "driver": "modbus"}]}
        self.write()

    def write(self):
        index = json.dumps({"format": "wyrm-images/1", "images": self.images}).encode()
        catalog = json.dumps(self.catalog).encode()
        (self.dir / "index.json").write_bytes(index)
        (self.dir / "catalog.json").write_bytes(catalog)
        lines = [f"{sha((self.dir / n).read_bytes())}  ./{n}"
                 for n in sorted(p.name for p in self.dir.iterdir()
                                 if p.name.endswith((".img.gz", ".manifest")))]
        lines += [f"{sha(index)}  index.json", f"{sha(catalog)}  catalog.json"]
        (self.dir / "SHA256SUMS").write_text("\n".join(lines) + "\n")


class FetchImagesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.boards = self.root / "boards.json"
        self.boards.write_text(json.dumps(BOARDS))
        self.out = self.root / "site/start/images"

    def tearDown(self):
        self.tmp.cleanup()

    def run_fetch(self, rel: Release, max_bytes: int = fi.MAX_MIB << 20) -> int:
        return fi.fetch(fi.DirSource(rel.dir), self.out, self.boards, max_bytes)

    def test_only_the_listed_boards_are_copied(self):
        rel = Release(self.root)
        self.assertEqual(self.run_fetch(rel), 2)
        names = sorted(p.name for p in self.out.iterdir())
        self.assertEqual(names, [
            "catalog.json", "index.json",
            "wyrm-bpi-r4-0.1.0-openwrt-25.12.6.img.gz", "wyrm-bpi-r4-0.1.0-openwrt-25.12.6.manifest",
            "wyrm-rpi4-0.1.0-openwrt-25.12.6.img.gz", "wyrm-rpi4-0.1.0-openwrt-25.12.6.manifest",
        ])
        index = json.loads((self.out / "index.json").read_text())
        self.assertEqual(index["format"], "wyrm-images/1")
        self.assertEqual([e["board"] for e in index["images"]], ["rpi4", "bpi-r4"])
        # the entries are the release's, unchanged
        self.assertEqual(index["images"][0], rel.images[0])
        self.assertEqual(json.loads((self.out / "catalog.json").read_text()), rel.catalog)
        # a source without a tag: the index names no release
        self.assertNotIn("release", index)

    def test_the_index_names_the_release_tag(self):
        rel = Release(self.root)
        self.assertEqual(fi.fetch(fi.DirSource(rel.dir, "images-v0.1.0-r2"), self.out, self.boards), 2)
        index = json.loads((self.out / "index.json").read_text())
        self.assertEqual(index["release"], "images-v0.1.0-r2")
        # a tag that is not one an images release has is left out
        for bad in ("v0.1.0", "images-v../x", "images-v1/2"):
            shutil.rmtree(self.out)
            fi.fetch(fi.DirSource(rel.dir, bad), self.out, self.boards)
            self.assertNotIn("release", json.loads((self.out / "index.json").read_text()), bad)

    def test_a_file_that_does_not_match_is_refused(self):
        rel = Release(self.root)
        gz = rel.dir / rel.images[2]["download"]["file"]
        data = bytearray(gz.read_bytes())
        data[20] ^= 0xFF
        gz.write_bytes(bytes(data))
        with self.assertRaisesRegex(fi.Refused, "SHA-256"):
            self.run_fetch(rel)
        self.assertFalse(self.out.exists(), "no file of the run is left")

        # a longer download, a changed manifest
        for change in ("long", "manifest"):
            with self.subTest(change):
                sub = self.root / change
                sub.mkdir()
                rel = Release(sub)
                if change == "long":
                    f = rel.dir / rel.images[0]["download"]["file"]
                    f.write_bytes(f.read_bytes() + b"\0")
                    pattern = "longer"
                else:
                    f = rel.dir / (rel.images[0]["file"][:-4] + ".manifest")
                    f.write_bytes(b"other\n")
                    pattern = "SHA-256"
                with self.assertRaisesRegex(fi.Refused, pattern):
                    self.run_fetch(rel)
                self.assertFalse(self.out.exists())

    def test_the_index_and_the_catalog_are_checked_against_the_sums(self):
        rel = Release(self.root)
        (rel.dir / "catalog.json").write_text('{"links": []}')
        with self.assertRaisesRegex(fi.Refused, "catalog.json: its SHA-256"):
            self.run_fetch(rel)
        self.assertFalse(self.out.exists())

    def test_the_size_cap_holds(self):
        rel = Release(self.root)
        with self.assertRaisesRegex(fi.Refused, "more than"):
            self.run_fetch(rel, max_bytes=1 << 20)
        self.assertFalse(self.out.exists(), "refused before anything is written")

    def test_a_name_that_is_not_plain_is_refused(self):
        for bad in ("../x.img.gz", "a/b.img.gz", ".hidden.img.gz", ""):
            with self.subTest(bad):
                sub = self.root / f"n{abs(hash(bad))}"
                sub.mkdir()
                rel = Release(sub)
                rel.images[0]["download"]["file"] = bad
                rel.write()
                with self.assertRaisesRegex(fi.Refused, "plain"):
                    self.run_fetch(rel)
                self.assertFalse(self.out.exists())

    def test_no_release_writes_nothing(self):
        empty = self.root / "empty"
        empty.mkdir()
        self.assertEqual(fi.fetch(fi.DirSource(empty), self.out, self.boards), 0)
        self.assertFalse(self.out.exists())


if __name__ == "__main__":
    unittest.main()
