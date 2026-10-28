# Example link packages

Packages to install with `sys/links` ▸ Install Link (ADR 0011). The guide is
[`docs/links.md`](../../docs/links.md); the link crates and how to install
each one are in [`examples/links`](../links/README.md).

`build.sh` builds the crates in `examples/links` and `links/probe` with
`wyr link pack` (each crate describes its package in
`[package.metadata.wyrm-link]`), the WASM components, and makes a
repository in `out/` with `wyr repo add` (ADR 0021; not in git):

| File | What it is | Install with |
|---|---|---|
| `out/index.json` | The repository index; urls relative to it. `examples/demo/run.sh` serves `out/` on `http://127.0.0.1:8090` (`REPO_PORT`). | `packages.repository` |
| `out/example-link/1.0.0/example-link-1.0.0-<os>-<arch>.zip` | Responder: the `mockdev` framework driver as its own binary (`examples/links/responder`). | from Zip, or from Repository |
| `out/recorder/1.0.0/recorder-1.0.0-<os>-<arch>.zip` | Requester: records `wy/{site}/downstream/mock` to CSV (`examples/links/requester`); asks for a `read` grant. | from Repository, Package `recorder` |
| `out/average/1.0.0/average-1.0.0-<os>-<arch>.zip` | Responder and requester: statistics of `wy/{site}/downstream/mock` and Write All (`examples/links/both`); asks for a `write` grant. | from Url `http://127.0.0.1:8090/average/1.0.0/average-1.0.0-<os>-<arch>.zip` |
| `out/probe/<version>/probe-<version>-<os>-<arch>.zip` | Test tool (`links/probe`). | from Repository, Package `probe` |
| `out/register/1.0.0/register-1.0.0.zip` | A WASM package (no network; one writable register per point, initially 7). | from Zip, or from Repository, Package `register` |
| `out/register.wasm` | The same component alone. | from WASM |
| `out/tcp-ping.wasm` | `init` takes a port (Config `5020`); `read` sends `ping` to `127.0.0.1:<port>` and returns the reply (needs `127.0.0.1:<port>` in Network). | from WASM |

A process zip carries the binary of one host. For other hosts, run
`wyr link pack --target <triple>` and `wyr repo add` the zips: they join
the same entry's `assets`.
