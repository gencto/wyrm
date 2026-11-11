# ADR 0041 — Claude connector: MCP through the user gateway

**Status:** accepted · 2026-11-10. Stage A (Claude Desktop extension) and stage B (a remote connector with OAuth on the gateway) are built and tested against a real gateway in-process. Stage B awaits a live test with claude.ai, once a public HTTPS name exists. Owner: "Claude should have a connector to WYRM. The chat we have needs a token; make it simpler for the user. Start with the desktop app, which we can test now; the HTTPS one we test later, when there is a domain."

## Context
Today an AI reaches WYRM three ways, and none of them is simple for an operator:
- **The agent link** (`links/agent`, ADR 0005): an LLM inside the broker. It needs an Anthropic API key in a link secret and is paid per token, not from the person's Claude plan.
- **`wyrm-mcp`** (ADR 0005): talks Zenoh to a router as the service account `ai:<agent>` with at most `write`. Config-level work needs a human approval token minted with an admin signing key (`wyr token …`). That is a key file and a command line for each change. Its HTTP transport is loopback only, with no TLS and no user login.
- **`wyrm-agent`** (ADR 0033): logs in to a gateway as a user. The identity is right: the user's role decides. But it is a command line for Claude Code.

Claude Desktop installs a local MCP server from one file (a `.mcpb` extension) with a settings form. Claude (web, Desktop and mobile) adds a remote MCP server by URL and logs in by OAuth 2.1. In both cases the person needs no API key and no token.

## Decision

### 1. One identity: a gateway user
The connector works as one user of a user gateway (ADR 0009), as Studio and `wyrm-agent` do. The gateway checks every request against that user's grants and signs a fresh `ptok` per request. The audit names `user:<name>`. The gateway reaches the sites below it (ADR 0007, 0018), so one connector reaches a chain of brokers. A user of its own for Claude (for example `claude` with the `operator` role) keeps Claude's changes apart in the audit. No new trust: whatever Claude can do, that user could do in Studio.

### 2. The tools (`wyrm_mcp::gateway::GatewayMcp`)
`whoami`, `tree_list`, `node_meta`, `value_get`, `value_watch`, `history`, `node_set`, `action_invoke`, `flow_deploy`, `plan_run`, `spec`, and the spec as resources. The operations are those of `wyrm-agent`. They moved from `links/agent/src/cli.rs` to `wyrm_mcp::gw`, so the CLI and the connector share one implementation (feature `gateway` of `wyrm-mcp`; `wyrm-agent` re-exports them).
- A path without `wy/` is taken below the gateway's own site (`/api/me` `site`). `wy/<other>/…` is passed as given, and the gateway decides.
- Changes default to `dry_run: true`. A dry run checks against the live `~meta` (type, enum, bounds, action schema, level) and returns `would_send`, plus `refused_by_connector` when a local switch would stop it.
- MCP annotations: reads are `readOnlyHint`, changes are `destructiveHint`, so the client asks the person before a change runs.

### 3. Two local switches on top of the role
The person who installs the connector sets them. They only narrow the role.
- `read_only` refuses every change.
- `allow_config` (off by default) lets config-level changes through: a `~set` on `writable = config`, an action of level `config`, anything under `wy/<site>/sys/**` on any site, a flow deploy. When it is off, they are refused before anything is sent. A plan is checked step by step against the live `~meta` before each step runs, and a node that does not exist yet counts as config.

The approval tokens of `wyrm-mcp`'s Zenoh mode are not used here. The gateway already signs for a person, and the person approves each tool call in the client.

### 4. Stage A — Claude Desktop extension (done)
- `wyrm-mcp --gateway <url> --user <name>`, with the password from `WYR_GATEWAY_PASSWORD`, serves stdio. Without `--gateway`, `wyrm-mcp` works as before.
- `wyrm-gateway-client` speaks `https://host[:port]`: rustls on ring, HTTP/1.1 ALPN, WSS. The roots are a PEM file (`--gateway-ca`: the broker CA, or a self-signed certificate) or the public web roots. Plain `http://` stays loopback only, because the password would go in clear.
- The session is opened lazily. It is opened again when the socket closes (expiry, a revoked session, a broker rebuild) or within 60 s of expiry. A read that fails on a dying socket runs once more. The password stays in memory (`Zeroizing`) and is never logged.
- `packaging/claude-desktop/`: `manifest.json` (MCPB 0.3, binary server; settings `gateway_url`, `user`, `password` (sensitive: kept in the OS keychain by Claude Desktop), `gateway_ca`, `read_only`, `allow_config`), `pack.py` (the zip) and `build.sh` (this machine; `--universal` gives one macOS binary). CI workflow `packaging/claude-desktop/ci-workflow.yml` (to be copied to `.github/workflows/claude-desktop.yml`) builds the macOS and Windows bundles.
- Settings arrive as environment variables. An optional setting left empty may arrive as an empty string or as the raw `${user_config.x}`. Both mean "not set". A switch is on only for `true`/`1`/`yes`/`on`, so an unfilled `allow_config` is off.

### 5. Stage B — a remote connector (built; `gateway.mcp`, off by default)
The gateway serves `/mcp` (streamable HTTP) itself and is its own OAuth 2.1 authorization server:
- `/.well-known/oauth-protected-resource` and `/.well-known/oauth-authorization-server` (RFC 9728, RFC 8414);
- dynamic client registration (RFC 7591) at `/oauth/register`, which Claude uses to register itself. Clients are stateless: the `client_id` is a sealed token of the redirect URIs and the name. Redirect URIs are limited to an allowlist in `gateway.mcp.redirect_uris`: by default Claude's two callbacks and `loopback` (any port on 127.0.0.1/localhost/::1, RFC 8252);
- `/oauth/authorize` with PKCE S256 only: one page with the gateway's own login (the same users, argon2id, failure limits, audit) and the consent, which names the client, where it returns, and the site. **Allow changes** (on) and **Allow config-level changes** (off; it needs the first) become the session's `read_only`/`allow_config`. The page is `no-store`, `X-Frame-Options: DENY`, and `frame-ancestors 'none'`. A bad client or redirect shows an error page and never redirects. The redirect carries `code`, `state` and `iss` (RFC 9207). Each sign-in is audited (`McpGranted`, `mcp_sign_in`);
- `/oauth/token`: codes live in memory (60 s, single use, ≤ 1024 waiting), bound to the client, the redirect URI and the challenge. Access tokens (≤ 1 h) and refresh tokens (30 days) are sealed (`Sealer`, own key `wyrm-gateway/oauth/v1`, a kind byte per sort) and carry the user's generation. A new password, a disabled user or a removed user ends them. A refresh token is bound to its client. Refresh tokens are not single use: they are stateless, like the sessions, and end by expiry or by the user's generation;
- `/mcp` (rmcp streamable HTTP, `Host` limited to the public name) checks the bearer on every request and resolves the user as now. It runs the same `GatewayMcp` tools in process, over the WebSocket protocol handler through an in-memory pipe (`ws::serve_frames`, `Conn::from_raw`), one pipe per live access token. Grants, rate limits, the socket budget and the audit are those of any gateway socket. An access token is never a gateway session (`/api/*` refuses it).
- OAuth and MCP are JSON by their own standards (`serde_json` at this edge only); the WYRM wire stays CBOR.

Off by default (`gateway.mcp` in `wyrmd.json5`, `GatewayConfig::mcp`; feature `mcp` of `wyrm-gateway`, default on). It needs TLS and a name that Claude's servers can reach. That is the cost: the gateway is reachable from the internet. Put it behind a reverse proxy with an allowlist of Anthropic's published egress ranges, or use the stage A extension, which needs no inbound access.

## Consequences
- An operator installs one file, enters a gateway URL, a user and a password, and Claude works within that user's role. There is no API key, and the use counts against the person's Claude plan.
- `wyrm-agent`'s operations live in `wyrm-mcp` now. A fix there reaches both the CLI and the connector.
- `wyrm-gateway-client` is no longer loopback only. Tools that used it (probe, tests) are unchanged: they still pass `http://127.0.0.1:…`.

*If wrong:* nothing is widened. The gateway, the user's grants and the responders decide as they do for Studio. The switches only remove options.
