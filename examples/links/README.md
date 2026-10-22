# Example links

Three links that show the roles a link can have, as in DSA (responder,
requester, both). Each one is a process package built by
`examples/packages/build.sh`; each is installed by a different path. The
guide is [`docs/links.md`](../../docs/links.md).

| Crate | Role | What it does | Grant it asks for |
|---|---|---|---|
| `responder` (`wyrm-example-link`) | responder | The `mockdev` framework driver as its own binary: connections, devices and points from its Add actions. | none |
| `requester` (`wyrm-example-recorder`) | requester | Follows every value under `wy/<site>/down/mock` and writes `time,key,value,quality` to `values.csv` in its data directory (rotated at `max_mb`). Serves no nodes. | `wy/{site}/down/mock` read |
| `both` (`wyrm-example-average`) | responder and requester | Follows the same values and serves `average`, `min`, `max`, `count`; its action **Write All** `{value}` sets every point it has seen, with `ptok`s signed by its requester key. | `wy/{site}/down/mock` write |

Params of the requester and both (set with `sys/links/<id>` ▸ Update Params):
`source` (default `wy/<site>/down/mock`), `max_mb` (requester only).

## Install them, each by another path

Run `examples/packages/build.sh`, then `examples/demo/run.sh` (it serves
`examples/packages/out` as the edge site's repository). On the edge gateway
(`http://127.0.0.1:8444`, user `admin`), open `wy/edge/sys/links`:

| Example | Install Link ▸ | Fields |
|---|---|---|
| responder | from Zip | Name `example`, Zip `out/example-link-<os>-<arch>.zip` |
| requester | from Repository | Name `rec`, Package `recorder` |
| both | from Url | Name `avg`, Url `http://127.0.0.1:8090/average-<os>-<arch>.zip` |
| WASM | from WASM | Name `reg`, Component `out/register.wasm` |
| built-in driver | from Driver, or `links` in `wyrmd.json5` | as `mock`, `lab` and `plc1` in `examples/demo/edge.json5` |

The install result lists the grants a package got
(`…; grant wy/{site}/down/mock read`). Then:

- requester: `examples/demo/data/edge/links/rec/data/values.csv` grows;
  `sys/links/rec` ▸ Get Log shows `recording` and `recorded`.
- both: `wy/edge/down/avg` shows the statistics; ▸ Write All `{value: 42}`
  answers `{written: 16, failed: []}` and the mock points show 42.
- Grants: `sys/links/<id>` ▸ Grant Access `{path, level}` changes them
  (`none` removes); `sys` ▸ Get Permissions lists them.

*from Git* takes HTTPS repositories only (a `file://` URL only in the
`dev` profile), so the demo does not use it: push a directory with
`wyrm-link.json` and the built binaries to a public HTTPS repository, then
install it with Url and Ref.
