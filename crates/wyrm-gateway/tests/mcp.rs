//! The remote MCP endpoint (ADR 0041 stage B) end to end: discovery, client registration,
//! the sign-in page, the code with PKCE, MCP calls with the bearer, refresh, revocation.
//! Raw HTTP/1.1 over TCP, as Claude's servers would send it (minus TLS).

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde_json::{json, Value as Json};
use sha2::{Digest, Sha256};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::oneshot;
use wyrm_gateway::{Gateway, GatewayConfig, McpConfig};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::{isolated_config, SITE};
use wyrm_link_sdk::LinkConfig;

const REDIRECT: &str = "http://127.0.0.1:9/callback";
const VERIFIER: &str = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";

struct Resp {
    status: u16,
    head: String,
    body: String,
}

impl Resp {
    fn header(&self, name: &str) -> Option<String> {
        self.head.lines().find_map(|l| {
            let (k, v) = l.split_once(':')?;
            k.eq_ignore_ascii_case(name).then(|| v.trim().to_owned())
        })
    }

    fn json(&self) -> Json {
        serde_json::from_str(&self.body).unwrap_or(Json::Null)
    }

    /// The JSON-RPC message of an MCP answer: plain JSON or the `data:` of an SSE stream.
    fn rpc(&self) -> Json {
        if let Ok(j) = serde_json::from_str::<Json>(&self.body) {
            return j;
        }
        self.body
            .lines()
            .filter_map(|l| l.strip_prefix("data:"))
            .filter_map(|d| serde_json::from_str::<Json>(d.trim()).ok())
            .find(|j| j.get("id").is_some())
            .unwrap_or(Json::Null)
    }
}

async fn http(
    addr: SocketAddr,
    method: &str,
    path: &str,
    headers: &[(&str, &str)],
    body: &str,
) -> Resp {
    let mut req = format!(
        "{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nConnection: close\r\nContent-Length: {}\r\n",
        addr.port(),
        body.len()
    );
    for (k, v) in headers {
        req.push_str(&format!("{k}: {v}\r\n"));
    }
    req.push_str("\r\n");
    req.push_str(body);
    let mut s = TcpStream::connect(addr).await.unwrap();
    s.write_all(req.as_bytes()).await.unwrap();
    let mut raw = Vec::new();
    tokio::time::timeout(Duration::from_secs(10), s.read_to_end(&mut raw))
        .await
        .expect("answer in time")
        .unwrap();
    let text = String::from_utf8_lossy(&raw).to_string();
    let (head, body) = text.split_once("\r\n\r\n").unwrap_or((&text, ""));
    let status = head.split(' ').nth(1).unwrap().parse().unwrap();
    // chunked bodies (SSE): keep the payload lines, drop the chunk sizes
    let body = if head
        .to_ascii_lowercase()
        .contains("transfer-encoding: chunked")
    {
        let mut out = String::new();
        let mut rest = body;
        while let Some((size, after)) = rest.split_once("\r\n") {
            let Ok(n) = usize::from_str_radix(size.trim(), 16) else {
                break;
            };
            if n == 0 || after.len() < n {
                break;
            }
            out.push_str(&after[..n]);
            rest = after[n..].trim_start_matches("\r\n");
        }
        out
    } else {
        body.to_owned()
    };
    Resp {
        status,
        head: head.to_owned(),
        body,
    }
}

fn form(kv: &[(&str, &str)]) -> String {
    kv.iter()
        .map(|(k, v)| format!("{k}={}", urlencode(v)))
        .collect::<Vec<_>>()
        .join("&")
}

fn urlencode(s: &str) -> String {
    s.bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"-._~".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect()
}

fn query_param(url: &str, k: &str) -> Option<String> {
    url.split_once('?')?.1.split('&').find_map(|kv| {
        let (a, b) = kv.split_once('=')?;
        (a == k).then(|| b.to_owned())
    })
}

struct Env {
    gw: Arc<Gateway>,
    addr: SocketAddr,
    stop: Option<oneshot::Sender<()>>,
}

impl Env {
    async fn start(name: &str) -> Self {
        let port = std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let dir =
            std::env::temp_dir().join(format!("wyrm-gateway-mcp-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let listen: SocketAddr = format!("127.0.0.1:{port}").parse().unwrap();
        let mut cfg = GatewayConfig::new(SITE, &dir, listen);
        cfg.mcp = Some(McpConfig::new(format!("http://127.0.0.1:{port}")));
        let gw = Gateway::open(cfg, b"test state key").unwrap();
        gw.ensure_admin("root", "root password").unwrap();
        gw.add_user("olena", "olena password", vec!["operator".into()])
            .unwrap();

        let session = zenoh::open(isolated_config()).await.unwrap();
        let mut lc = LinkConfig::new(SITE, "mock");
        lc.admin_keys = vec![gw.verifying_key()];
        lc.answer_val = true;
        let link = wyrm_link_sdk::spawn::<Mock>(
            session.clone(),
            lc,
            MockConfig {
                points: 2,
                rate_hz: 0.0,
                depth: 0,
                fanout: 1,
                writable: true,
            },
        )
        .await
        .unwrap();
        std::mem::forget(link); // lives for the test process
        let (stop, rx) = oneshot::channel::<()>();
        tokio::spawn(gw.clone().serve(session, async {
            let _ = rx.await;
        }));
        let addr = tokio::time::timeout(Duration::from_secs(5), gw.local_addr())
            .await
            .unwrap();
        Self {
            gw,
            addr,
            stop: Some(stop),
        }
    }

    /// Register, sign in with `consent` checkboxes, trade the code: `(client_id, token json)`.
    async fn sign_in(&self, write: bool, config: bool) -> (String, Json) {
        let r = http(
            self.addr,
            "POST",
            "/oauth/register",
            &[("Content-Type", "application/json")],
            &json!({ "redirect_uris": [REDIRECT], "client_name": "Claude", "token_endpoint_auth_method": "none" }).to_string(),
        )
        .await;
        assert_eq!(r.status, 201, "{}", r.body);
        let client_id = r.json()["client_id"].as_str().unwrap().to_owned();
        let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(VERIFIER.as_bytes()));
        let params = [
            ("response_type", "code"),
            ("client_id", client_id.as_str()),
            ("redirect_uri", REDIRECT),
            ("code_challenge", challenge.as_str()),
            ("code_challenge_method", "S256"),
            ("state", "xyz"),
            ("scope", "wyrm"),
        ];
        let page = http(
            self.addr,
            "GET",
            &format!("/oauth/authorize?{}", form(&params)),
            &[],
            "",
        )
        .await;
        assert_eq!(page.status, 200, "{}", page.body);
        assert!(
            page.body.contains("Connect Claude to WYRM"),
            "{}",
            page.body
        );
        assert_eq!(page.header("x-frame-options").as_deref(), Some("DENY"));

        let mut f: Vec<(&str, &str)> = params.to_vec();
        f.extend([
            ("user", "olena"),
            ("password", "wrong"),
            ("decision", "allow"),
        ]);
        let bad = http(
            self.addr,
            "POST",
            "/oauth/authorize",
            &[("Content-Type", "application/x-www-form-urlencoded")],
            &form(&f),
        )
        .await;
        assert_eq!(bad.status, 401);
        assert!(bad.body.contains("wrong user or password"));

        let mut f: Vec<(&str, &str)> = params.to_vec();
        f.extend([
            ("user", "olena"),
            ("password", "olena password"),
            ("decision", "allow"),
        ]);
        if write {
            f.push(("write", "on"));
        }
        if config {
            f.push(("config", "on"));
        }
        let ok = http(
            self.addr,
            "POST",
            "/oauth/authorize",
            &[("Content-Type", "application/x-www-form-urlencoded")],
            &form(&f),
        )
        .await;
        assert_eq!(ok.status, 302, "{}", ok.body);
        let loc = ok.header("location").unwrap();
        assert!(loc.starts_with(REDIRECT), "{loc}");
        assert_eq!(query_param(&loc, "state").as_deref(), Some("xyz"));
        let code = query_param(&loc, "code").unwrap();

        let trade = |verifier: &'static str, code: String| {
            let client_id = client_id.clone();
            async move {
                http(
                    self.addr,
                    "POST",
                    "/oauth/token",
                    &[("Content-Type", "application/x-www-form-urlencoded")],
                    &form(&[
                        ("grant_type", "authorization_code"),
                        ("code", &code),
                        ("redirect_uri", REDIRECT),
                        ("client_id", &client_id),
                        ("code_verifier", verifier),
                    ]),
                )
                .await
            }
        };
        let wrong = trade("x".repeat(43).leak(), code.clone()).await;
        assert_eq!(
            wrong.json()["error"],
            json!("invalid_grant"),
            "{}",
            wrong.body
        );
        // a code is spent by any attempt
        let again = trade(VERIFIER, code).await;
        assert_eq!(again.json()["error"], json!("invalid_grant"));

        // a fresh sign-in, traded right
        let ok = http(
            self.addr,
            "POST",
            "/oauth/authorize",
            &[("Content-Type", "application/x-www-form-urlencoded")],
            &form(&f),
        )
        .await;
        let code = query_param(&ok.header("location").unwrap(), "code").unwrap();
        let t = trade(VERIFIER, code).await;
        assert_eq!(t.status, 200, "{}", t.body);
        (client_id, t.json())
    }

    async fn mcp(&self, token: &str, session: Option<&str>, msg: Json) -> Resp {
        let auth = format!("Bearer {token}");
        let mut h = vec![
            ("Content-Type", "application/json"),
            ("Accept", "application/json, text/event-stream"),
            ("Authorization", auth.as_str()),
        ];
        if let Some(s) = session {
            h.push(("Mcp-Session-Id", s));
        }
        http(self.addr, "POST", "/mcp", &h, &msg.to_string()).await
    }

    /// initialize + initialized: the session id.
    async fn open(&self, token: &str) -> String {
        let r = self
            .mcp(
                token,
                None,
                json!({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                    "protocolVersion": "2025-06-18", "capabilities": {},
                    "clientInfo": {"name": "test", "version": "0"}}}),
            )
            .await;
        assert_eq!(r.status, 200, "{} {}", r.head, r.body);
        let sid = r.header("mcp-session-id").unwrap();
        let n = self
            .mcp(
                token,
                Some(&sid),
                json!({"jsonrpc": "2.0", "method": "notifications/initialized"}),
            )
            .await;
        assert!(n.status == 202 || n.status == 200, "{}", n.status);
        sid
    }

    async fn call(&self, token: &str, sid: &str, tool: &str, args: Json) -> (bool, Json) {
        let r = self
            .mcp(
                token,
                Some(sid),
                json!({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": tool, "arguments": args}}),
            )
            .await;
        assert_eq!(r.status, 200, "{} {}", r.head, r.body);
        let res = &r.rpc()["result"];
        let text = res["content"][0]["text"]
            .as_str()
            .unwrap_or_default()
            .to_owned();
        (
            res["isError"] == json!(true),
            serde_json::from_str(&text).unwrap_or(Json::String(text)),
        )
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn claude_signs_in_and_works_through_the_mcp_endpoint() {
    let env = Env::start("flow").await;
    let base = format!("http://127.0.0.1:{}", env.addr.port());

    let pr = http(
        env.addr,
        "GET",
        "/.well-known/oauth-protected-resource",
        &[],
        "",
    )
    .await;
    assert_eq!(pr.json()["resource"], json!(format!("{base}/mcp")));
    let asm = http(
        env.addr,
        "GET",
        "/.well-known/oauth-authorization-server",
        &[],
        "",
    )
    .await;
    assert_eq!(
        asm.json()["code_challenge_methods_supported"],
        json!(["S256"])
    );

    // a redirect off the allowlist does not register
    let r = http(
        env.addr,
        "POST",
        "/oauth/register",
        &[("Content-Type", "application/json")],
        &json!({ "redirect_uris": ["https://evil.example/cb"] }).to_string(),
    )
    .await;
    assert_eq!(r.json()["error"], json!("invalid_redirect_uri"));

    // no bearer: 401 that points at the metadata
    let r = http(
        env.addr,
        "POST",
        "/mcp",
        &[("Content-Type", "application/json")],
        "{}",
    )
    .await;
    assert_eq!(r.status, 401);
    assert!(r
        .header("www-authenticate")
        .unwrap()
        .contains("resource_metadata="));

    let (client_id, t) = env.sign_in(true, false).await;
    let access = t["access_token"].as_str().unwrap().to_owned();
    let refresh = t["refresh_token"].as_str().unwrap().to_owned();
    assert_eq!(t["token_type"], json!("Bearer"));

    // the access token is no gateway session
    let me = http(
        env.addr,
        "GET",
        "/api/me",
        &[("Authorization", &format!("Bearer {access}"))],
        "",
    )
    .await;
    assert_eq!(me.status, 401);

    let sid = env.open(&access).await;
    let (e, who) = env.call(&access, &sid, "whoami", json!({})).await;
    assert!(!e, "{who}");
    assert_eq!(who["user"], json!("olena"));
    assert_eq!(
        who["connector"],
        json!({ "read_only": false, "allow_config": false })
    );

    // approving an agent's plan is for a person (ADR 0049): refused before anything is
    // read or sent, a dry run too
    for dry_run in [true, false] {
        let (e, r) = env
            .call(
                &access,
                &sid,
                "action_invoke",
                json!({ "path": "downstream/agent/tasks/1", "action": "approve",
                        "args": { "steps": [1], "plan": "h" }, "dry_run": dry_run }),
            )
            .await;
        assert!(e && r.as_str().unwrap().contains("for a person"), "{r}");
    }

    let (e, w) = env
        .call(
            &access,
            &sid,
            "node_set",
            json!({ "path": "downstream/mock/p0", "value": 12.5, "dry_run": false }),
        )
        .await;
    assert!(!e, "{w}");
    let mut v = Json::Null;
    for _ in 0..20 {
        let (_, g) = env
            .call(
                &access,
                &sid,
                "value_get",
                json!({ "paths": ["downstream/mock/p0"] }),
            )
            .await;
        v = g["downstream/mock/p0"]["v"].clone();
        if v == json!(12.5) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert_eq!(v, json!(12.5));

    // refresh: another client cannot, the right one gets new tokens
    let refresh_with = |cid: String| {
        let refresh = refresh.clone();
        async move {
            http(
                env.addr,
                "POST",
                "/oauth/token",
                &[("Content-Type", "application/x-www-form-urlencoded")],
                &form(&[
                    ("grant_type", "refresh_token"),
                    ("refresh_token", &refresh),
                    ("client_id", &cid),
                ]),
            )
            .await
        }
    };
    assert_eq!(
        refresh_with("other".into()).await.json()["error"],
        json!("invalid_grant")
    );
    let t2 = refresh_with(client_id.clone()).await.json();
    let access2 = t2["access_token"].as_str().unwrap().to_owned();
    let (e, _) = env.call(&access2, &sid, "whoami", json!({})).await;
    assert!(!e);

    // a new password ends every grant of the user
    env.gw.set_password("olena", "new password").unwrap();
    let r = env
        .mcp(
            &access2,
            Some(&sid),
            json!({"jsonrpc": "2.0", "id": 3, "method": "tools/list"}),
        )
        .await;
    assert_eq!(r.status, 401);
    assert_eq!(
        refresh_with(client_id).await.json()["error"],
        json!("invalid_grant")
    );

    if let Some(s) = env.stop {
        let _ = s.send(());
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_read_only_consent_is_kept() {
    let env = Env::start("ro").await;
    let (_, t) = env.sign_in(false, true).await;
    let access = t["access_token"].as_str().unwrap().to_owned();
    let sid = env.open(&access).await;
    let (_, who) = env.call(&access, &sid, "whoami", json!({})).await;
    // config without write means nothing: both off
    assert_eq!(
        who["connector"],
        json!({ "read_only": true, "allow_config": false })
    );
    let (e, r) = env
        .call(
            &access,
            &sid,
            "node_set",
            json!({ "path": "downstream/mock/p1", "value": 1, "dry_run": false }),
        )
        .await;
    assert!(e && r.as_str().unwrap().contains("read-only"), "{r}");
    if let Some(s) = env.stop {
        let _ = s.send(());
    }
}
