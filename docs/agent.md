# AI agent link (`links/agent`)

`links/agent` has two parts:

1. **`wyrm-agent`, the command line** (below): an operator or an AI assistant (Claude Code)
   runs it on a workstation and works on the whole broker network through one gateway.
2. **The `agent` driver**: an LLM inside the broker that plans tasks for people to approve
   (from "How a task runs" on).

## `wyrm-agent`: the command line

Build it once:

```sh
cargo build --release -p wyrm-link-agent --features cli --bin wyrm-agent
```

It logs in to a gateway as one of its users. The password comes from
`WYR_GATEWAY_PASSWORD`, never from the command line. The user's role decides every read and
write. The gateway reaches the sites below its own, so central's gateway works on edge and
plant too (ADR 0007, 0018).

| Command | What it does |
|---|---|
| `tree <key> [--depth N]` | The nodes below a key: type, unit, writable. |
| `meta <key>` | The full `~meta`: actions with their parameters, levels, bounds. |
| `get <key>…` | Current values. |
| `watch <pattern> [--seconds N]` | Samples of a key or a pattern for a while. |
| `set <key> <json>` | Writes a value. |
| `invoke <key> <action> [<json args>]` | Runs an action. |
| `history <key> <json args>` | Recorded values (`{"from": "…", "limit": 100}`). |
| `run <plan.json> [--apply]` | Checks a plan; with `--apply`, runs it. |

Every answer is JSON, one object per line. The exit code is 1 when a plan check or a step
fails.

### Plans

A plan is `{"steps": [...]}`, run in order. A step is one of:

- `{"invoke": <key>, "action": …, "args": {…}, "unless": <key>, "ok_if_error": <text>}`: runs
  the action; skipped when `unless` exists, and done when the action is refused with a message
  that holds `ok_if_error` (`"is watched"`: it is so already). With these the same plan runs
  again;
- `{"set": <key>, "value": …}`;
- `{"deploy": "wy/<site>/dataflows", "def": {…}}`: deploys a flow one version above the one
  that runs (the gateway signs the proofs of its targets with your rights);
- `{"wait": <key>, "timeout_s": N}`: waits until the node exists;
- `{"expect": <key>, "equals": …}` or `"min"`/`"max"` or `"changes": true`, with
  `timeout_s`: waits until the value passes;
- `{"sleep_s": N}`.

1. Run `run <plan>` first. It checks each step against the live `~meta`: the action exists,
   its arguments fit its schema, a value fits its point. A step on a node an earlier step
   makes is checked when it runs (`"check": "later"`).
2. Read the result, then run `run <plan> --apply`. It stops at the first step that fails and
   says which.

УВАГА: `--apply` changes the sites at once, with your rights. Read the check first.

### Example: a Modbus device, history, upstream and a dataflow

`examples/agent/modbus-dataflow.json` runs on the demo (`examples/demo/run.sh`) through
central's gateway:

```sh
export WYR_GATEWAY_PASSWORD=wyrm-demo-1
wyrm-agent --gateway http://127.0.0.1:8445 run examples/agent/modbus-dataflow.json
wyrm-agent --gateway http://127.0.0.1:8445 run examples/agent/modbus-dataflow.json --apply
```

It adds the device `ahu2` with four points on edge's Modbus link, records two of them on edge
and one on central (central's historian records a point of the site below), deploys a flow on
edge that turns the counter into a command (`count mod 10 × 10`) and the temperature into °F
and a flag, and on each change writes the command to another link (`mockdev/bench/rig1/knob`).
The last steps check the flow's values and that the knob follows.

## The `agent` driver

The `agent` driver takes a task in plain words, asks an LLM for a plan, and runs the plan
after a human approves it (ADR 0005). It runs embedded in `wyrmd`
(`sys/links ▸ Install Link ▸ from Driver`, driver `agent`).

## How a task runs

1. A user with `write` on the link calls ▸ **Ask** `{task}`. The link creates `tasks/<id>`.
   `{task, parent, context}` may name a task this one follows (a retry, an undo) and node keys
   to read first.
2. The model reads the tree with read-only tools. It may ask back (`ask_user`): the task waits
   in `awaiting_answer` until ▸ **Answer** `{answers}`.
3. The model proposes a plan. `set` and `invoke` steps change the site. `wait`, `expect` and
   `sleep` steps only read: they prove the plan and need no approval.
4. The link checks every step against `~meta`, `allowed_prefixes` and the level the step needs.
5. With approval needed, the task waits in `awaiting_approval`. The record is the task's
   `~state` document (restricted: the reader needs `list`): `plan[]` holds every step in the
   `wyrm-agent run` format with its number `n`, level, `after`, `check`, `warn` and `reason`.
   ▸ **Approve** `{approvals: {"<n>": <token>}, plan}` takes one human token per step, at the
   level of that step. `write` on the task is enough to call it.
6. The link runs the stored plan. A step with a human token runs with that human's rights. A
   step without a token that needs one is `skipped`, and so is every step that needs it
   (`after`). The run stops at the first step that fails.

The agent never runs a `config` step without a human token.

Who approves decides what runs without a token:

- The asker of the task, or a user with `config` on the link: a `write` step that needs no
  approval runs with the agent's own key (`ai:<link>`, at most `write`, only under
  `allowed_prefixes`).
- Any other user: only the steps they sign run. Every other step that changes something is
  `skipped`.

### Through a gateway

A gateway user holds no key. Send `approve {steps: [n…], plan: <hash>}`: the gateway reads the
stored plan, checks your grants for each step and signs one token per step (ADR 0049). `plan`
is the hash of the plan you read: SHA-256 (hex) of the canonical CBOR of `~state.plan`, each
step without `approval`, `check`, `warn`, `reason`, `result` (`planHash` in `wyrm_client`).
A step outside your grants refuses the whole call and names the step and the right.

The gateway signs only:

- for a person's own session. A session of an MCP client (the Claude connector, `/mcp`) is
  refused, and the connector itself never sends `approve` for a task: approve in Studio.
- for a task of an agent link of the gateway's own site, as the broker's registry knows it
  (driver `agent`). A task on a downstream site is refused for now: approve it through that
  site's gateway, or with your own tokens.

### An approval does not wait

An approval token is made when you approve and is good for a few minutes (5 min from the
gateway; never more than 15 min, spec 04). The run sends each step in its turn, after the
waits of the proof steps before it. So:

- The link takes no step that needs a person into a plan when the waits before it
  (`wait`/`expect` timeouts, `sleep`) add up to more than 240 s. The model is told to shorten
  the waits or to end the plan there.
- ▸ **Approve** is refused, and the task keeps waiting, when a token cannot outlive the waits
  before its step plus 30 s. Leave the step out; it is `skipped`.
- Ask for the rest as a follow-up (`ask {parent}`) when the plan is done, and approve it then.
  A token is never made for later.

The gateway op `doc {key, suffix: "~state"}` reads the record.

### What a task shows

| Key | Who reads | What |
|---|---|---|
| `tasks/<id>/~val` | read on the link | `{state, step, of, last: {n, ok, result}}`: numbers and fixed words only |
| `tasks/<id>/~state` | `list` on the task | the ask, owner, plan with results, questions, log, error |
| `budget_used_today` | read on the link | LLM tokens used this UTC day |
| `sys/links/<id>` ▸ `secrets` | `config` | the names of the link's secrets, never a value |

## Params

| Param | Default | Meaning |
|---|---|---|
| `model` | `claude-sonnet-5-5` | The model. |
| `budget_tokens_day` | 1 000 000 | LLM tokens per UTC day; Ask is refused at the limit. |
| `allowed_prefixes` | none | Keys under which the agent may propose changes. Empty: nothing. |
| `require_approval` | `write` | Which steps need a human (below). |
| `api_key_ref` | `anthropic_api_key` | The link secret with the API key (▸ Set Secret). |
| `api_base` | `https://api.anthropic.com` | Where the API key is sent. |
| `max_turns`, `max_tokens`, `llm_timeout_s`, `fallbacks` | | Bounds of one planning run. |

## Approval modes

- `write` (default): every step needs a human token. Keep this mode.
- `config` and `never`: only `config` steps need a human; `write` steps run at once with the
  agent's key.

УВАГА: with `config` or `never`, the model's plan writes without a human. The model reads
text that devices and users put in the tree: node names, descriptions, enum names, values,
profiles, flow definitions. Anyone who can write such text can try to steer the plan
(prompt injection). Use these modes only with narrow `allowed_prefixes`, and only where
every write there is safe to make without review (security review AI-4, ADR 0031).

ОБЕРЕЖНО: the `reason` and `warn` of a step, a question's text and the model's log lines come
from the model too. Before you approve, read each step's key and arguments in `plan`, not only
the reason.

## The API key and `api_base`

The API key is entered once with ▸ **Set Secret** (`anthropic_api_key`) and is never shown.
It goes only to `api_base`, over TLS with the system roots.

The secret may also hold an OAuth access token of the `ant` CLI (it starts with `sk-ant-oat`;
`ant auth print-credentials --access-token` prints it after `ant auth login`). The link then
sends it as `Authorization: Bearer`. Such a token lasts some hours and the link does not
refresh it: when Ask fails with `HTTP 401`, set the secret again. Use it to try the assistant;
give a broker that runs for long an API key.

A change of `api_base` (▸ Update with another host or path) deletes the API key secret. Enter
the key again after the change; the audit shows `secret_dropped`. A user with `config` on the
link cannot read the secret, and this rule stops them from sending the key to a host of their
own (security review AI-3, ADR 0031).
