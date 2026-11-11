#!/usr/bin/env python3
"""Pack `wyrm-mcp` into a Claude Desktop extension (`.mcpb`, ADR 0041).

    python3 packaging/claude-desktop/pack.py --binary target/release/wyrm-mcp --platform darwin
    python3 packaging/claude-desktop/pack.py --binary target/release/wyrm-mcp.exe --platform win32

An `.mcpb` is a zip: `manifest.json` at the root, the server under `server/`. The manifest is
this directory's `manifest.json` with the workspace version and the platform filled in.
`build.sh` builds the binary and calls this.
"""

import argparse
import json
import pathlib
import re
import sys
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
PLATFORMS = ("darwin", "win32", "linux")


def workspace_version() -> str:
    text = (ROOT / "Cargo.toml").read_text(encoding="utf-8")
    m = re.search(r'^\[workspace\.package\][^\[]*?^version\s*=\s*"([^"]+)"', text, re.M | re.S)
    if not m:
        sys.exit("no [workspace.package] version in Cargo.toml")
    return m.group(1)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--binary", required=True, type=pathlib.Path, help="the built wyrm-mcp")
    ap.add_argument("--platform", required=True, choices=PLATFORMS)
    ap.add_argument("--out", type=pathlib.Path, default=ROOT / "dist" / "claude-desktop")
    a = ap.parse_args()
    if not a.binary.is_file():
        sys.exit(f"{a.binary}: no such file (build it first: cargo build --release -p wyrm-mcp)")

    version = workspace_version()
    manifest = (HERE / "manifest.json").read_text(encoding="utf-8")
    manifest = manifest.replace("@VERSION@", version).replace("@PLATFORMS@", a.platform)
    json.loads(manifest)  # still JSON after the fill-in

    exe = "wyrm-mcp.exe" if a.platform == "win32" else "wyrm-mcp"
    a.out.mkdir(parents=True, exist_ok=True)
    target = a.out / f"wyrm-{version}-{a.platform}.mcpb"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("manifest.json", manifest)
        icon = HERE / "icon.png"
        if icon.is_file():
            z.write(icon, "icon.png")
        info = zipfile.ZipInfo(f"server/{exe}")
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (0o100755 << 16)  # a regular file, rwxr-xr-x on unpack
        z.writestr(info, a.binary.read_bytes())
    print(target)


if __name__ == "__main__":
    main()
