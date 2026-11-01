# AI agent link (`links/agent`)

The `agent` driver takes a task in plain words, asks an LLM for a plan, and runs the plan
after a human approves it (ADR 0005). It runs embedded in `wyrmd`
(`sys/links ▸ Install Link ▸ from Driver`, driver `agent`).

## How a task runs

1. A user with `write` on the link calls ▸ **Ask** `{task}`. The link creates `tasks/<id>`.
2. The model reads the tree with read-only tools and proposes a plan: a list of `set` and
   `invoke` steps.
3. The link checks every step against `~meta`, `allowed_prefixes` and the level the step needs.
4. With approval needed, the task waits in `awaiting_approval`. A user with `config` reads
   `tasks/<id>/~val` (`plan` holds every step with its key and arguments) and calls
   ▸ **Approve** with one human token per step, or ▸ **Reject**.
5. The link runs the stored plan. A step with a human token runs with that human's rights; a
   `write` step that needs no approval runs with the agent's own key (`ai:<link>`, at most
   `write`, only under `allowed_prefixes`).

The agent never runs a `config` step without a human token.

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

ОБЕРЕЖНО: the `reason` of a step and the model's log lines come from the model too. Before
you approve, read each step's key and arguments in `plan`, not only the reason.

## The API key and `api_base`

The API key is entered once with ▸ **Set Secret** (`anthropic_api_key`) and is never shown.
It goes only to `api_base`, over TLS with the system roots.

A change of `api_base` (▸ Update with another host or path) deletes the API key secret. Enter
the key again after the change; the audit shows `secret_dropped`. A user with `config` on the
link cannot read the secret, and this rule stops them from sending the key to a host of their
own (security review AI-3, ADR 0031).
