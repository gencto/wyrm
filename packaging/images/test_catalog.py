#!/usr/bin/env python3
"""Test of catalog.py: the catalog of links the board images offer.

    python3 packaging/images/test_catalog.py

Standard library only.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog  # noqa: E402

OFFICIAL = json.loads((catalog.REPO / "links/official.json").read_text(encoding="utf-8"))


def package(path: Path, name: str) -> None:
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(catalog.MANIFEST, json.dumps({"name": name, "version": "0.1.0"}))


class CatalogTest(unittest.TestCase):
    def test_the_official_links_without_seeds(self):
        out = catalog.catalog(OFFICIAL, {})
        rows = {r["id"]: r for r in out["links"]}
        for s in catalog.SERVICES:
            self.assertEqual(rows[s]["form"], "service")
            self.assertNotIn("driver", rows[s])
        self.assertEqual(rows["modbus"], {
            "id": "modbus", "form": "builtin", "driver": "modbus", "title": "Modbus",
            "category": "Equipment", "summary": rows["modbus"]["summary"]})
        # a link that ships only as a package is offered only when the image carries it
        self.assertNotIn("postgres", rows)
        self.assertNotIn("telegram", rows)
        # the order of official.json
        order = [l["id"] for l in OFFICIAL["links"]]
        ids = [r["id"] for r in out["links"]]
        self.assertEqual(ids, [i for i in order if i in rows])

    def test_a_seed_package_is_offered_with_its_file(self):
        with tempfile.TemporaryDirectory() as d:
            package(Path(d) / "telegram-0.1.0.wyrm-link", "telegram")
            out = catalog.catalog(OFFICIAL, catalog.seeds(Path(d)))
        row = [r for r in out["links"] if r["id"] == "telegram"][0]
        self.assertEqual((row["form"], row["file"]), ("seed", "telegram-0.1.0.wyrm-link"))

    def test_files_that_are_no_offered_package_are_refused(self):
        with tempfile.TemporaryDirectory() as d:
            package(Path(d) / "x.zip", "not-a-link")
            with self.assertRaisesRegex(catalog.CatalogError, "no official link"):
                catalog.catalog(OFFICIAL, catalog.seeds(Path(d)))
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "seed.json").write_text("{}")
            with self.assertRaisesRegex(catalog.CatalogError, "packages only"):
                catalog.seeds(Path(d))
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "junk.zip").write_bytes(b"not a zip")
            with self.assertRaisesRegex(catalog.CatalogError, "no package"):
                catalog.seeds(Path(d))
        with tempfile.TemporaryDirectory() as d:
            package(Path(d) / "a.zip", "slack")
            package(Path(d) / "b.zip", "slack")
            with self.assertRaisesRegex(catalog.CatalogError, "also"):
                catalog.seeds(Path(d))


if __name__ == "__main__":
    unittest.main()
