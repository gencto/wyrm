# Claude connector — WYRM in Claude Desktop (ADR 0041)

Claude works on your broker network as one gateway user. It reads the tree, values and history. After a dry run that you approve, it writes values, runs actions, deploys dataflows and runs checked plans. The user's role decides what is allowed. You need no API key: Claude Desktop runs the connector on your computer, and it logs in to the gateway like Studio does.

## 1. A gateway user for Claude
Create a user of its own, so the audit shows which changes Claude made. On the broker host, run this (the password is read from stdin):

```bash
wyrmd -c wyrmd.json5 user add claude --roles operator
```

| Role | What Claude can do |
|---|---|
| `viewer` | read devices and storage |
| `operator` | read, write points, run write-level actions, read flows |
| `engineer` | also config-level work: add/edit devices, deploy flows (needs **Allow config-level changes** too) |

## 2. Install the extension
1. Get `wyrm-<version>-darwin.mcpb` (macOS) or `wyrm-<version>-win32.mcpb` (Windows) from the CI run of **claude-desktop** (Actions → claude-desktop → Artifacts; the workflow is `packaging/claude-desktop/ci-workflow.yml`, copied to `.github/workflows/claude-desktop.yml`), or build it yourself:
   ```bash
   packaging/claude-desktop/build.sh --universal
   ```
   The file goes to `dist/claude-desktop/`. On Windows, run `bash packaging/claude-desktop/build.sh` from Git Bash.
2. Double-click the file, or in Claude Desktop open **Settings → Extensions → Install Extension…**.
3. Fill in the form:

| Setting | Value |
|---|---|
| Gateway URL | `https://<broker>:<port>`. For a gateway on this computer (the demo), `http://127.0.0.1:8445`. Plain HTTP to another host is refused, because the password would go in clear. |
| Gateway user / Password | the user from step 1. Claude Desktop keeps the password in the system keychain. |
| Gateway CA certificate | the PEM that signs the gateway's certificate: the broker CA, or the certificate itself when it is self-signed. Leave it empty for a certificate from a public CA. |
| Read-only | refuses every change |
| Allow config-level changes | off by default. When it is off, Claude can show config-level changes (config points and actions, anything under `sys`, flow deploys) but not send them. |

4. Start a chat and ask "who are you on WYRM?". Claude calls `whoami` and answers with the user, the site and the grants.

## 3. What to expect
- Before a change, Claude reads the node's `~meta`, runs a dry run and shows what it would send. Claude Desktop asks you before each tool call. Allow only what you have read.
- Several dependent steps (add a device, wait for it, set a value, expect a reading) go in one `plan_run`. Claude checks the plan first and applies it after you agree.
- Keys: `downstream/modbus/plc1/temp` means a key on the gateway's own site. `wy/<site>/…` reaches a site below it.
- When the session expires (8 h by default), the connector logs in again by itself.

## 4. When it does not work

| Message | Cause |
|---|---|
| `wrong user or password, or the user is disabled` | Fix the settings under Settings → Extensions → WYRM. |
| `TLS: invalid peer certificate: UnknownIssuer` | Set **Gateway CA certificate** to the PEM of the broker CA or of the self-signed certificate. |
| `plain HTTP only on loopback` | Use `https://` for a gateway on another host. The gateway serves TLS when `tls_cert`/`tls_key` are set in `wyrmd.json5`. |
| `Connection refused` | The gateway is not running, or the port is wrong (`gateway.listen` in `wyrmd.json5`). |
| `refused_by_connector: … allow_config` | A config-level change. Turn on **Allow config-level changes** if the user's role should be used for it, or do it in Studio. |
| `permission_denied` | The user's role does not allow it. |

Logs: in Claude Desktop, open **Settings → Developer**, or open the extension's log file (`mcp-server-WYRM.log`).

## Claude Code and other MCP clients
The same binary runs anywhere MCP runs:

```json
{
  "mcpServers": {
    "wyrm": {
      "command": "/abs/target/release/wyrm-mcp",
      "args": ["--gateway", "https://broker.example:8445", "--user", "claude", "--gateway-ca", "/abs/broker-ca.pem"],
      "env": { "WYR_GATEWAY_PASSWORD": "…" }
    }
  }
}
```

Without `--gateway`, `wyrm-mcp` is the Zenoh-side server with approval tokens ([mcp.md](mcp.md)).

## Claude on the web and mobile: the remote connector
The gateway serves an MCP endpoint at `https://<broker>/mcp` itself, with its own OAuth 2.1 sign-in (ADR 0041 stage B). You add it once on claude.ai, and it works on the web, in Desktop and on mobile. It is off by default. It needs a public HTTPS name that Claude's servers can reach.

1. In `wyrmd.json5`:
   ```json5
   gateway: {
     listen: "0.0.0.0:8445",
     tls_cert: "/etc/wyrm/gateway.pem",   // a certificate for broker.example from a public CA
     tls_key: "/etc/wyrm/gateway.key",
     mcp: {
       public_url: "https://broker.example:8445",
       // optional: redirect_uris (default: Claude's callbacks and "loopback"),
       // access_ttl_s (60…3600, default 3600), refresh_days (1…365, default 30)
     },
   },
   ```
   Restart `wyrmd`. `https://broker.example:8445/.well-known/oauth-protected-resource` now answers with JSON.
2. On claude.ai, open **Settings → Connectors → Add custom connector**, name it `WYRM`, and set the URL to `https://broker.example:8445/mcp`. No client ID or secret is needed: Claude registers itself.
3. Claude opens the gateway's sign-in page. Enter the gateway user (step 1 above) and the password, choose **Allow changes** and/or **Allow config-level changes**, and sign in.

What is checked:
- Only redirect URIs on the allowlist register: Claude's callbacks, and loopback for MCP clients on your own computer.
- The code is single use, lasts 60 s, and is bound to PKCE S256.
- An access token lasts at most 1 h and is valid only on `/mcp`, never as a Studio session.
- Refresh tokens are bound to the client. A new password, a disabled user or a removed user ends every token.
- Each sign-in is in the audit as `mcp_sign_in`, with the client's name and what was allowed.

Exposure: the gateway is reachable from the internet. Put it behind a reverse proxy that passes `/mcp`, `/oauth/*` and `/.well-known/oauth-*` and allows only Anthropic's published egress IP ranges for `/mcp` and `/oauth/token`. The sign-in page itself opens in your browser. If you cannot expose the gateway, use the Desktop extension above: it needs no inbound access.
