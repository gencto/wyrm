# Example links

Three links that show the roles a link can have, as in DSA (responder,
requester, both), and one portable link. Each one is a package built by
`examples/packages/build.sh`; each is installed by a different path. The
guide is [`docs/links.md`](../../docs/links.md).

| Crate | Role | What it does | Grant it asks for |
|---|---|---|---|
| `responder` (`wyrm-example-link`) | responder | The `mockdev` framework driver as its own binary: connections, devices and points from its Add actions. | none |
| `requester` (`wyrm-example-recorder`) | requester | Follows every value under `wy/<site>/downstream/mock` and writes `time,key,value,quality` to `values.csv` in its data directory (rotated at `max_mb`). Serves no nodes. | `wy/{site}/downstream/mock` read |
| `both` (`wyrm-example-average`) | responder and requester | Follows the same values and serves `average`, `min`, `max`, `count`; its action **Write All** `{value}` sets every point it has seen, with `ptok`s signed by its requester key. | `wy/{site}/downstream/mock` write |
| `portable` (`wyrm-example-portable`) | responder, portable (ADR 0023) | One `App` (`Echo`) in three modes: embedded (`wyrmd` driver `portable-echo`), a process package (`portable-echo-process`) and a WASM package (`portable-echo`). Serves `n` (writable, kept in its store), `ticks`, `starts`; actions **Ping** (a 50 ms timer, answers `pong`) and **Echo** `{value}`. Params: `faults: true` adds **Crash** (a trap; the host restarts it). | none |

Params of the requester and both (set with `sys/links/<id>` ▸ Update Params):
`source` (default `wy/<site>/downstream/mock`), `max_mb` (requester only).

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
| portable, WASM | from Repository | Name `echo`, Package `portable-echo` |
| portable, process | from Repository | Name `echop`, Package `portable-echo-process` |
| portable, embedded | from Driver | Name `echoe`, Driver `portable-echo` |
| built-in driver | from Driver, or `links` in `wyrmd.json5` | as `mock`, `lab` and `plc1` in `examples/demo/edge.json5` |

The install result lists the grants a package got
(`…; grant wy/{site}/downstream/mock read`). Then:

- requester: `examples/demo/data/edge/links/rec/data/values.csv` grows;
  `sys/links/rec` ▸ Get Log shows `recording` and `recorded`.
- both: `wy/edge/downstream/avg` shows the statistics; ▸ Write All `{value: 42}`
  answers `{written: 16, failed: []}` and the mock points show 42.
- portable: in each of the three modes, set `n`, ▸ Ping (`ticks` goes to 1 after 50 ms),
  then `sys/links/<id>` ▸ Stop and ▸ Start: `starts` goes up by one and `n` comes back from
  the store. `crates/wyrmd/tests/e2e.rs` `one_app_three_modes` runs this scenario.
- Grants: `sys/links/<id>` ▸ Grant Access `{path, level}` changes them
  (`none` removes); `sys` ▸ Get Permissions lists them.

*from Git* takes HTTPS repositories only (a `file://` URL only in the
`dev` profile), so the demo does not use it: push a directory with
`wyrm-link.json` and the built binaries to a public HTTPS repository, then
install it with Url and Ref.
