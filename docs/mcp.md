# wyrm-mcp — the WYRM tree as MCP tools (ADR 0005)

`tools/wyrm-mcp` is an MCP server over `wyrm-client` (stdio; streamable HTTP on loopback with `--http`). It signs requests as `ai:<agent-name>` with at most `write`; without `--key` it is read-only.

## Tools
`tree_list`, `tree_resolve`, `node_meta` (`expand` applies profiles), `value_get`, `node_set`, `action_invoke`, `profiles`, `flow_get`, `flow_validate`, `flow_apply`, `link_status`, `spec`; resources `wy://spec/<file>`.

- `node_set`, `action_invoke` and `flow_apply` default to `dry_run: true`: they validate against `~meta` (type, enum, bounds, action schema, level) and return what would be sent.
- Config-level operations (`writable = config`, action level `config`, anything under `sys/**`, flow deploys) need `approval`: a base64 `ptok` minted by a human for exactly that key **and exactly those arguments** (≤ 15 min, subject not `ai:`). It is sent instead of the service token, so the link checks the human's rights. `flow_apply` also needs one proof per command target from the same human (ADR 0008).
- An approval is bound to the arguments (claim `args`, spec 04 0.2.14; security review AI-1). Without it an MCP client could show a harmless dry run, get the token, then send other arguments with it. The steps:
  1. Run the tool with `dry_run` (the default). Read `would_send` (for `flow_apply`: the definition and the proofs) and copy `args_sha256`.
  2. Mint the approval for that key and that hash: `wyr --key admin.key token <key> --subject user:<you> --args-sha256 <hash> [--ttl-s 300]`.
  3. Run the tool again with the same arguments, `dry_run: false` and `approval`.
- The MCP server refuses an approval without `args` or with another hash before it sends anything; the link refuses it too.
- For `flow_apply`, give the proofs in the dry run already: they are part of the request, so the hash covers them.

## Claude Code
WARNING: the key file is an admin signing key. Keep it at mode 0600.

1. Run `cargo build --release -p wyrm-mcp`.
2. Put this in `.mcp.json` (absolute paths):
```json
{
  "mcpServers": {
    "wyrm": {
      "command": "/abs/wyrm/target/release/wyrm-mcp",
      "args": ["--connect", "tcp/127.0.0.1:7447", "--site", "local", "--agent-name", "claude"],
      "env": { "WYRM_MCP_KEY": "/abs/ai.key" }
    }
  }
}
```
For HTTP: run `wyrm-mcp --http 127.0.0.1:8765` (set `WYRM_MCP_HTTP_TOKEN`, at least 32 characters, or copy the random token it prints) and use `{"type": "http", "url": "http://127.0.0.1:8765/mcp", "headers": {"Authorization": "Bearer <token>"}}`. Requests need a loopback `Host` with that port and no `Origin` header (DNS-rebinding guard).

## Not yet
Tools `history`, `device_models`, `link_install`; tree and profile resources; prompts; `origin` marking for approved AI calls; a service identity issued by the admin (the `write` cap is enforced by the MCP process); TLS for `--http` (loopback only, bearer token).
