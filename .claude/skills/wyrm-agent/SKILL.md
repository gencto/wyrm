---
name: wyrm-agent
description: Work on a running WYRM broker network (the demo or a real one) through a gateway — read the tree, run actions, set values, deploy flows, and run checked plans — with the wyrm-agent CLI. Use when asked to configure devices, history, upstream storage or dataflows on live brokers, or to check what a live site holds.
---

# wyrm-agent

1. Build: `cargo build -p wyrm-link-agent --features cli --bin wyrm-agent` (debug is fine).
2. Credentials: `export WYR_GATEWAY_PASSWORD=…` (demo: `wyrm-demo-1`, user `admin`). Gateways in the demo: central `http://127.0.0.1:8445` (reaches edge and plant), edge `:8444`, plant `:8446`.
3. Read before you change: `wyrm-agent --gateway <url> tree <key> --depth 2`, `meta <key>` (the actions and their parameter schemas — copy names and enums from here, never guess), `get <key>…`.
4. For more than one change, write a plan (`docs/agent.md` › Plans; example `examples/agent/modbus-dataflow.json`) and run `run <plan>` (check), read every line, then `run <plan> --apply`. Use `unless` on create steps, `wait` after a create, `expect` to prove the result.
5. Every output line is JSON; exit code 1 = a check or a step failed: read its `error`.
6. Flows: `deploy` steps take a spec 06 `def`; sources only under the site's `downstream`, `dataflows` or `storage`; command targets (`set`, `invoke`) get proofs from the gateway with your rights.
7. After changes to the demo's tree, run `wyr probe` on the three sites (CLAUDE.md rule).
