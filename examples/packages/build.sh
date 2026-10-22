#!/usr/bin/env bash
# Build the example link packages into examples/packages/out/ (ADR 0011):
#
#   example-link-<os>-<arch>.zip  process package: the wyrm-example-link
#                                 binary (mockdev driver) for this host
#   register-wasm.zip             wasm package: the register component
#   register.wasm, tcp-ping.wasm  components for "Install Link ▸ from WASM"
#   index.json                    repository index for "from Repository",
#                                 URLs on http://127.0.0.1:${REPO_PORT:-8090}
#
# examples/demo/run.sh serves out/ on that port when it exists.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../..
OUT=out
PORT=${REPO_PORT:-8090}
mkdir -p "$OUT"

(cd $ROOT && cargo build --release -p wyrm-example-link)
(cd $ROOT && cargo run -q -p wyrm-link-wasm --example components -- examples/packages/$OUT)

PROTO=$(sed -n 's/^pub const LINK_PROTOCOL: u32 = \([0-9]*\);/\1/p' $ROOT/crates/wyrm-link-sdk/src/lib.rs)

python3 -I - "$OUT" "$ROOT/target/release/wyrm-example-link" "$PROTO" "$PORT" <<'PY'
import hashlib, json, platform, sys, zipfile
from pathlib import Path

out, binary, proto, port = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
os_name = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}[platform.system()]
arch = {"arm64": "aarch64", "aarch64": "aarch64", "x86_64": "x86_64", "AMD64": "x86_64"}[platform.machine()]
host = f"{os_name}-{arch}"

def put(z, name, data, mode=0o644):
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.external_attr = mode << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(info, data)

def package(path, manifest, files):
    with zipfile.ZipFile(path, "w") as z:
        put(z, "wyrm-link.json", json.dumps(manifest, indent=2) + "\n")
        for name, data, mode in files:
            put(z, name, data, mode)
    return path

entry = f"bin/{host}/wyrm-example-link"
proc_zip = package(out / f"example-link-{host}.zip", {
    "name": "example-link",
    "version": "1.0.0",
    "description": "Example process link: the mockdev driver as its own binary",
    "wyrm_link": proto,
    "kind": "process",
    "entries": {host: entry},
}, [(entry, binary.read_bytes(), 0o755)])

wasm_zip = package(out / "register-wasm.zip", {
    "name": "register",
    "version": "1.0.0",
    "description": "Example WASM link: one writable register per point, no network",
    "wyrm_link": proto,
    "kind": "wasm",
    "entry": "register.wasm",
}, [("register.wasm", (out / "register.wasm").read_bytes(), 0o644)])

def item(name, version, description, path):
    return {
        "name": name,
        "version": version,
        "description": description,
        "url": f"http://127.0.0.1:{port}/{path.name}",
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }

index = [
    item("example-link", "1.0.0", "Example process link (mockdev)", proc_zip),
    item("register", "1.0.0", "Example WASM link (register)", wasm_zip),
]
(out / "index.json").write_text(json.dumps(index, indent=2) + "\n")
for p in sorted(out.iterdir()):
    print(f"{p.stat().st_size:>10}  {p}")
PY
