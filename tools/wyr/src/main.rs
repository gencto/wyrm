//! `wyr` — WYRM command line. Node keys are full keys without suffix:
//! `wyr list wy/local/down/mock/g0`.
//!
//! Developer commands (wiki "AI-агент, MCP і CLI" §3): `new link|flow`
//! (templates in `tools/wyr/templates`), `dev` (flow hot reload), `sim`
//! (mock link), `record`/`replay` (flows on recorded samples), `tree`,
//! `watch` (= `sub`). See `tools/wyr/README.md`.

/// `println!` that exits quietly when stdout is closed (`wyr … | head`).
macro_rules! out {
    ($($t:tt)*) => {{
        use std::io::Write as _;
        if writeln!(std::io::stdout(), $($t)*).is_err() {
            std::process::exit(0);
        }
    }};
}

mod admin;
mod bench;
mod dev;
mod flow;
mod replay;
mod scaffold;
mod sim;

use clap::{Parser, Subcommand};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use wyrm_client::endpoint::TlsFiles;
use wyrm_client::{ListEvent, SigningTokens, ValEvent, WyrmClient};
use wyrm_core::meta::{Profile, TextOrCode};
use wyrm_core::{NodeMeta, Quality, Value};

type Error = Box<dyn std::error::Error + Send + Sync>;

#[derive(Parser, Debug)]
#[command(version, about = "WYRM command line")]
struct Cli {
    /// Router endpoint.
    #[arg(long, global = true, default_value = "tcp/127.0.0.1:7447")]
    connect: String,
    /// Admin signing key file (from `wyr keygen`); mints a ptok per request.
    #[arg(long, global = true, env = "WYR_KEY")]
    key: Option<PathBuf>,
    /// CA certificate for `tls/`/`quic/` endpoints.
    #[arg(long, global = true, env = "WYR_CA")]
    ca: Option<PathBuf>,
    /// Client certificate (CN = operator name) for `tls/`/`quic/` endpoints.
    #[arg(long, global = true, env = "WYR_CERT")]
    cert: Option<PathBuf>,
    /// Private key of `--cert` (`--key` is the admin signing key).
    #[arg(long = "tls-key", global = true, env = "WYR_TLS_KEY")]
    tls_key: Option<PathBuf>,
    /// Request timeout, seconds.
    #[arg(long, global = true, default_value_t = 10)]
    timeout: u64,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Children of a node (`wy/<site>/down` lists links).
    List {
        node: String,
        /// Keep running and print changes.
        #[arg(short, long)]
        watch: bool,
    },
    /// Full ~meta of a node.
    Meta { node: String },
    /// Descendant keys, optionally filtered (`type:1;unit:°C`).
    Resolve {
        node: String,
        #[arg(long = "match")]
        matcher: Option<String>,
        #[arg(long)]
        depth: Option<usize>,
    },
    /// Recursive listing (one `list` per branch), depth-limited.
    Tree {
        #[arg(default_value = "wy/local/down")]
        node: String,
        #[arg(long, default_value_t = 3)]
        depth: usize,
    },
    /// Live values for a node pattern (`wy/local/down/mock/**`).
    #[command(visible_alias = "watch")]
    Sub {
        pattern: String,
        /// QoS 2/3: publisher history first, then live, with gap recovery.
        #[arg(long)]
        reliable: bool,
    },
    /// Recorded values of a point (`~val?history=`, needs a watch in
    /// `sys/history`): `--from 2026-10-22T08:00:00Z [--to …] [--agg avg
    /// --window 5m]`. (`wyr history` is a link's params history.)
    Values {
        node: String,
        /// RFC 3339 or a date (`2026-10-22` = its midnight UTC).
        #[arg(long)]
        from: String,
        /// Default: now.
        #[arg(long, default_value = "")]
        to: String,
        /// avg, min, max, sum, count, first, last, delta, and, or.
        #[arg(long)]
        agg: Option<String>,
        /// One row per window: 30s, 5m, 1h, 1d.
        #[arg(long)]
        window: Option<String>,
        #[arg(long)]
        limit: Option<usize>,
    },
    /// Write a value: `true`, `21.5`, `3`, `null` or any text.
    Set { node: String, value: String },
    /// Run an action with `name=value` arguments.
    Invoke {
        node: String,
        action: String,
        args: Vec<String>,
    },
    /// Latency benchmarks.
    Bench {
        #[command(subcommand)]
        what: bench::What,
    },
    /// Data flows (`wy/<site>/flows`).
    Flow {
        #[command(subcommand)]
        cmd: flow::FlowCmd,
    },
    #[command(flatten)]
    Admin(admin::AdminCmd),
    /// Scaffold a driver crate or a flow definition.
    New {
        #[command(subcommand)]
        what: scaffold::NewCmd,
    },
    /// Hot reload: watch `<flows>/*.json5`, validate and deploy on change.
    Dev {
        #[arg(long, default_value = "flows")]
        flows: PathBuf,
        #[arg(long, default_value = "local")]
        site: String,
    },
    /// Simulated links in this process.
    Sim {
        #[command(subcommand)]
        what: sim::SimCmd,
    },
    /// Record live values of a pattern into a CBOR file (for `replay`).
    Record {
        pattern: String,
        #[arg(long)]
        out: PathBuf,
        /// Stop after this many seconds (default: Ctrl-C).
        #[arg(long)]
        secs: Option<u64>,
    },
    /// Run a flow definition offline on recorded samples; no broker needed.
    Replay {
        /// Recording from `wyr record`.
        file: PathBuf,
        /// Flow definition (JSON or JSON5).
        #[arg(long)]
        flow: PathBuf,
        /// Site the flow runs in (default: from the recorded keys).
        #[arg(long)]
        site: Option<String>,
        /// Replay speed; 1 = recorded pace.
        #[arg(long, default_value_t = 1.0)]
        speed: f64,
        /// Shorten longer pauses between samples to this many seconds
        /// (0 = keep them).
        #[arg(long, default_value_t = 5.0)]
        max_gap_s: f64,
        /// Wait after the last sample, milliseconds.
        #[arg(long, default_value_t = 1000)]
        settle_ms: u64,
    },
    /// Create an admin signing key (hex seed, mode 0600) and print the public key.
    /// Mint a human approval token for exactly one request key (base64), for
    /// `wyrm-mcp` / `links/agent` config-level operations. Needs --key.
    Token {
        /// Full request key, e.g. `wy/local/down/plc1/sp/~set`.
        key_expr: String,
        /// Your identity, e.g. `user:alice` (never `ai:`).
        #[arg(long)]
        subject: String,
        /// Highest permission the token grants.
        #[arg(long, default_value = "config")]
        perm: String,
        /// Lifetime in seconds (responders refuse more than 900).
        #[arg(long, default_value_t = 300)]
        ttl_s: u64,
    },
    Keygen {
        #[arg(long, default_value = "admin.key")]
        out: PathBuf,
    },
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    if let Err(e) = run(cli).await {
        eprintln!("error: {e}");
        std::process::exit(1);
    }
}

async fn run(cli: Cli) -> Result<(), Error> {
    // Commands that need no broker connection.
    match cli.cmd {
        Cmd::Keygen { out } => return keygen(&out),
        Cmd::Token {
            key_expr,
            subject,
            perm,
            ttl_s,
        } => {
            let key = cli.key.as_deref().ok_or("--key is required")?;
            println!(
                "{}",
                approval_token(load_key(key)?, &key_expr, &subject, &perm, ttl_s)?
            );
            return Ok(());
        }
        Cmd::New { what } => return scaffold::run(what),
        Cmd::Replay {
            file,
            flow,
            site,
            speed,
            max_gap_s,
            settle_ms,
        } => {
            replay::replay(replay::ReplayArgs {
                file,
                flow,
                site,
                speed,
                max_gap: (max_gap_s > 0.0)
                    .then(|| Duration::try_from_secs_f64(max_gap_s))
                    .transpose()
                    .map_err(|_| "--max-gap-s: not a valid duration")?,
                settle: Duration::from_millis(settle_ms),
            })
            .await?;
            return Ok(());
        }
        Cmd::Sim { what } => {
            let (ep, ca, cert, tls_key) = (&cli.connect, &cli.ca, &cli.cert, &cli.tls_key);
            let broker = || client_config(ep, ca, cert, tls_key);
            return sim::run(what, broker, &cli.key).await;
        }
        _ => {}
    }
    let client = connect(&cli).await?;
    match cli.cmd {
        Cmd::Tree { node, depth } => tree(&client, &node, depth).await,
        Cmd::Dev { flows, site } => {
            let c = client.with_site(&flow::root(&site), &cli.key)?;
            dev::run(&c, &site, &flows).await
        }
        Cmd::Record { pattern, out, secs } => replay::record(&client, &pattern, &out, secs).await,
        Cmd::List { node, watch } => list(&client, &node, watch).await,
        Cmd::Meta { node } => {
            out!("{}", fmt_meta(&client.meta(&node).await?));
            Ok(())
        }
        Cmd::Resolve {
            node,
            matcher,
            depth,
        } => {
            for k in client.resolve(&node, matcher.as_deref(), depth).await? {
                out!("{k}");
            }
            Ok(())
        }
        Cmd::Sub { pattern, reliable } => sub(&client, &pattern, reliable).await,
        Cmd::Values {
            node,
            from,
            to,
            agg,
            window,
            limit,
        } => {
            let q = wyrm_client::HistoryQuery {
                from,
                to,
                agg,
                window,
                limit,
            };
            for r in client.history(&node, &q).await? {
                let q = r.q.map_or("", |q| q.name());
                out!(
                    "{} {} {q}",
                    wyrm_history::time::iso_us(r.t),
                    fmt_value(&r.v)
                );
            }
            Ok(())
        }
        Cmd::Set { node, value } => {
            client
                .with_site(&node, &cli.key)?
                .set(&node, parse_value(&value))
                .await?;
            out!("ok");
            Ok(())
        }
        Cmd::Invoke { node, action, args } => {
            let mut map = BTreeMap::new();
            for a in &args {
                let (k, v) = parse_param(a)?;
                map.insert(k, v);
            }
            let c = client.with_site(&node, &cli.key)?;
            let mut s = c.invoke(&node, &action, Value::Map(map)).await?;
            let mut any = false;
            while let Some(item) = s.next().await {
                match item? {
                    Some(v) => out!("{}", fmt_value(&v)),
                    None => out!("ok"),
                }
                any = true;
            }
            if !any {
                out!("ok");
            }
            Ok(())
        }
        Cmd::Bench { what } => bench::run(&client.inner, what).await,
        Cmd::Flow { cmd } => {
            let c = client.with_site(&flow::root(cmd.site()), &cli.key)?;
            flow::run(&c, cmd).await
        }
        Cmd::Admin(cmd) => {
            let c = client.with_site(&format!("wy/{}/sys", cmd.site()), &cli.key)?;
            admin::run(&c, cmd).await
        }
        Cmd::Keygen { .. }
        | Cmd::Token { .. }
        | Cmd::New { .. }
        | Cmd::Replay { .. }
        | Cmd::Sim { .. } => {
            unreachable!("handled above")
        }
    }
}

/// Client plus what is needed to add tokens once the target site is known.
struct Ctx {
    inner: WyrmClient,
}

impl std::ops::Deref for Ctx {
    type Target = WyrmClient;
    fn deref(&self) -> &WyrmClient {
        &self.inner
    }
}

impl Ctx {
    /// A client that mints tokens for the site of `node` (`wy/<site>/…`).
    fn with_site(&self, node: &str, key: &Option<PathBuf>) -> Result<WyrmClient, Error> {
        let Some(path) = key else {
            return Ok(self.inner.clone());
        };
        let site = node
            .split('/')
            .nth(1)
            .filter(|_| node.starts_with("wy/"))
            .ok_or("node key must start with wy/<site>/")?;
        let tokens = SigningTokens::new(load_key(path)?, site);
        Ok(self.inner.clone().with_tokens(Arc::new(tokens)))
    }
}

/// Client-mode session config for `--connect` (with mTLS for `tls/`/`quic/`).
fn client_config(
    connect: &str,
    ca: &Option<PathBuf>,
    cert: &Option<PathBuf>,
    tls_key: &Option<PathBuf>,
) -> Result<zenoh::Config, Error> {
    let tls = tls_files(connect, ca, cert, tls_key)?;
    Ok(wyrm_client::endpoint::client_config(connect, tls.as_ref())?)
}

async fn connect(cli: &Cli) -> Result<Ctx, Error> {
    let zc = client_config(&cli.connect, &cli.ca, &cli.cert, &cli.tls_key)?;
    let session = zenoh::open(zc).await?;
    Ok(Ctx {
        inner: WyrmClient::new(session).with_timeout(Duration::from_secs(cli.timeout)),
    })
}

/// The mTLS files for `tls/`/`quic/` endpoints; `None` otherwise.
fn tls_files(
    endpoint: &str,
    ca: &Option<PathBuf>,
    cert: &Option<PathBuf>,
    key: &Option<PathBuf>,
) -> Result<Option<TlsFiles>, Error> {
    if !wyrm_client::endpoint::is_tls(endpoint) {
        return Ok(None);
    }
    let (Some(ca), Some(cert), Some(key)) = (ca, cert, key) else {
        return Err("tls/quic endpoints need --ca, --cert and --tls-key".into());
    };
    Ok(Some(TlsFiles {
        ca: ca.clone(),
        cert: cert.clone(),
        key: key.clone(),
    }))
}

/// `name=value` → (name, parsed value).
fn parse_param(a: &str) -> Result<(String, Value), Error> {
    match a.split_once('=') {
        Some((k, v)) if !k.is_empty() => Ok((k.to_owned(), parse_value(v))),
        _ => Err(format!("argument {a:?} is not name=value").into()),
    }
}

fn keygen(out: &Path) -> Result<(), Error> {
    if out.exists() {
        return Err(format!("{} exists; not overwriting", out.display()).into());
    }
    let mut seed = [0u8; 32];
    getrandom::fill(&mut seed).map_err(|e| format!("no randomness: {e}"))?;
    let key = ed25519_dalek::SigningKey::from_bytes(&seed);
    write_private(out, &hex::encode(seed))?;
    out!("{}", hex::encode(key.verifying_key().to_bytes()));
    eprintln!(
        "private key written to {}; put the public key above into wyrmd.json5 admin_keys",
        out.display()
    );
    Ok(())
}

#[cfg(unix)]
fn write_private(path: &Path, text: &str) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    writeln!(f, "{text}")
}

#[cfg(not(unix))]
fn write_private(path: &Path, text: &str) -> std::io::Result<()> {
    std::fs::write(path, format!("{text}\n"))
}

/// One-key approval token (see `Cmd::Token`).
fn approval_token(
    key: ed25519_dalek::SigningKey,
    key_expr: &str,
    subject: &str,
    perm: &str,
    ttl_s: u64,
) -> Result<String, Error> {
    use base64::Engine;
    use wyrm_client::TokenSource;
    let site = key_expr
        .strip_prefix("wy/")
        .and_then(|r| r.split('/').next())
        .filter(|s| !s.is_empty())
        .ok_or("key must start with wy/<site>/")?;
    if key_expr.contains('*') {
        return Err("an approval is for one exact key (no wildcards)".into());
    }
    if subject.starts_with("ai:") || !subject.contains(':') {
        return Err("subject: a human identity such as user:<name>".into());
    }
    if ttl_s == 0 || ttl_s > 900 {
        return Err("ttl-s: 1..=900".into());
    }
    let perm = wyrm_core::Perm::ALL
        .iter()
        .copied()
        .find(|p| p.name() == perm)
        .ok_or("perm: none|list|read|write|config")?;
    let tok = SigningTokens::new(key, site)
        .subject(subject)
        .max(perm)
        .ttl(Duration::from_secs(ttl_s))
        .token(key_expr)
        .ok_or("no grant covers this key")?;
    Ok(base64::engine::general_purpose::STANDARD.encode(tok))
}

fn load_key(path: &Path) -> Result<ed25519_dalek::SigningKey, Error> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let seed: [u8; 32] = hex::decode(text.trim())?
        .try_into()
        .map_err(|_| "key file must hold a 32-byte hex seed")?;
    Ok(ed25519_dalek::SigningKey::from_bytes(&seed))
}

async fn list(c: &WyrmClient, node: &str, watch: bool) -> Result<(), Error> {
    if !watch {
        for child in c.children(node).await? {
            out!("{}", fmt_child(&child.name, &child.meta));
        }
        return Ok(());
    }
    let mut s = c.list(node).await?;
    while let Some(ev) = s.next().await {
        match ev {
            ListEvent::Refreshed(kids) => {
                out!("= refreshed ({} children)", kids.len());
                for k in kids {
                    out!("  {}", fmt_child(&k.name, &k.meta));
                }
            }
            ListEvent::Added(k) => out!("+ {}", fmt_child(&k.name, &k.meta)),
            ListEvent::Changed(k) => out!("~ {}", fmt_child(&k.name, &k.meta)),
            ListEvent::Removed(n) => out!("- {n}"),
            ListEvent::Disconnected(None) => out!("! owner disconnected"),
            ListEvent::Disconnected(Some(n)) => out!("! {n} disconnected"),
            ListEvent::Connected(n) => out!("^ {n} connected"),
        }
    }
    Ok(())
}

/// Children of `node` pushed in reverse (popped in order) at `level`.
async fn push_children(
    c: &WyrmClient,
    node: &str,
    level: usize,
    stack: &mut Vec<(String, usize, String, NodeMeta)>,
) -> Result<(), Error> {
    for k in c.children(node).await?.into_iter().rev() {
        stack.push((format!("{node}/{}", k.name), level, k.name, k.meta));
    }
    Ok(())
}

/// Depth-first listing. Branches are expanded unless their meta says they
/// have no children; an error is shown only where children were expected.
async fn tree(c: &WyrmClient, node: &str, depth: usize) -> Result<(), Error> {
    out!("{node}");
    let mut stack = Vec::new();
    if depth > 0 {
        push_children(c, node, 1, &mut stack).await?;
    }
    while let Some((path, level, name, meta)) = stack.pop() {
        out!("{}{}", "  ".repeat(level), fmt_child(&name, &meta));
        if level < depth && meta.has_children != Some(false) {
            if let Err(e) = push_children(c, &path, level + 1, &mut stack).await {
                if meta.has_children == Some(true) {
                    out!("{}! {e}", "  ".repeat(level + 1));
                }
            }
        }
    }
    Ok(())
}

async fn sub(c: &WyrmClient, pattern: &str, reliable: bool) -> Result<(), Error> {
    let mut s = if reliable {
        c.subscribe_reliable(pattern).await?
    } else {
        c.subscribe(pattern).await?
    };
    while let Some(ev) = s.next().await {
        match ev {
            ValEvent::Sample { key, sample, qual } => {
                let q = match (sample.q, qual) {
                    (_, Some(q)) => q,
                    (Quality::Good, None) => String::new(),
                    (q, None) => q.name().to_owned(),
                };
                out!("{key} = {} {q}", fmt_value(&sample.v));
            }
            ValEvent::Removed(key) => out!("{key} removed"),
        }
    }
    Ok(())
}

fn parse_value(s: &str) -> Value {
    match s {
        "true" => Value::Bool(true),
        "false" => Value::Bool(false),
        "null" => Value::Null,
        _ => s
            .parse::<i64>()
            .map(Value::from)
            .or_else(|_| s.parse::<f64>().map(Value::Float))
            .unwrap_or_else(|_| Value::Str(s.to_owned())),
    }
}

fn fmt_value(v: &Value) -> String {
    match v {
        Value::Null => "null".into(),
        Value::Bool(b) => b.to_string(),
        Value::Int(i) => i.to_string(),
        Value::UInt(u) => u.to_string(),
        Value::Float(f) => f.to_string(),
        Value::Str(s) => format!("{s:?}"),
        Value::Bytes(b) => format!("0x{}", hex::encode(b)),
        Value::Array(a) => format!(
            "[{}]",
            a.iter().map(fmt_value).collect::<Vec<_>>().join(", ")
        ),
        Value::Map(m) => format!(
            "{{{}}}",
            m.iter()
                .map(|(k, v)| format!("{k}: {}", fmt_value(v)))
                .collect::<Vec<_>>()
                .join(", ")
        ),
    }
}

fn fmt_profile(p: &Option<Profile>) -> String {
    match p {
        Some(Profile::Name(n)) => n.clone(),
        Some(Profile::Code(c)) => format!("#{c}"),
        None => "-".into(),
    }
}

fn fmt_child(name: &str, m: &NodeMeta) -> String {
    let mut s = format!("{name:<24} {:<10}", fmt_profile(&m.is));
    if let Some(t) = m.ty {
        s.push_str(&format!(" {}", t.name()));
    }
    if m.has_children == Some(true) {
        s.push_str(" /");
    }
    if let Some(d) = &m.display {
        s.push_str(&format!("  {d:?}"));
    }
    s
}

fn fmt_meta(m: &NodeMeta) -> String {
    let mut lines = vec![format!("is        {}", fmt_profile(&m.is))];
    if let Some(t) = m.ty {
        lines.push(format!("type      {}", t.name()));
    }
    if let Some(u) = &m.unit {
        lines.push(match u {
            TextOrCode::Text(t) => format!("unit      {t}"),
            TextOrCode::Code(c) => format!("unit      #{c}"),
        });
    }
    if let Some(w) = m.writable {
        lines.push(format!("writable  {}", w.name()));
    }
    if let Some(i) = m.invokable {
        lines.push(format!("invokable {}", i.name()));
    }
    for (name, map) in [("cfg", &m.cfg), ("attr", &m.attr)] {
        if let Some(map) = map {
            for (k, v) in map {
                lines.push(format!("{name}.{k:<6} {}", fmt_value(v)));
            }
        }
    }
    if let Some(acts) = &m.actions {
        for (name, a) in acts {
            let params: Vec<_> = a.params.keys().cloned().collect();
            lines.push(format!("action    {name}({})", params.join(", ")));
        }
    }
    if let Some(c) = &m.children {
        const SHOWN: usize = 16;
        let mut line = c.iter().take(SHOWN).cloned().collect::<Vec<_>>().join(" ");
        if c.len() > SHOWN {
            line.push_str(&format!(" … ({} total, see `wyr list`)", c.len()));
        }
        lines.push(format!("children  {line}"));
    }
    if let Some(r) = m.rev {
        lines.push(format!("rev       {r}"));
    }
    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn values() {
        assert_eq!(parse_value("true"), Value::Bool(true));
        assert_eq!(parse_value("3"), Value::UInt(3));
        assert_eq!(parse_value("-3"), Value::Int(-3));
        assert_eq!(parse_value("21.5"), Value::Float(21.5));
        assert_eq!(parse_value("on"), Value::Str("on".into()));
    }

    #[test]
    fn params() {
        assert_eq!(
            parse_param("port=502").unwrap(),
            ("port".into(), Value::UInt(502))
        );
        assert_eq!(
            parse_param("host=a=b").unwrap(),
            ("host".into(), Value::Str("a=b".into()))
        );
        assert!(parse_param("noequals").is_err());
        assert!(parse_param("=1").is_err());
    }

    #[test]
    fn tls_flags() {
        let p = |s: &str| Some(PathBuf::from(s));
        assert!(tls_files("tcp/127.0.0.1:7447", &None, &None, &None)
            .unwrap()
            .is_none());
        assert!(tls_files("tls/127.0.0.1:7448", &p("ca"), &None, &p("k")).is_err());
        let zc =
            client_config("tls/127.0.0.1:7448", &p("ca.pem"), &p("c.pem"), &p("c.key")).unwrap();
        assert_eq!(
            zc.get_json("transport/link/tls/enable_mtls").unwrap(),
            "true"
        );
    }

    #[test]
    fn admin_cli_parses() {
        let cli = Cli::try_parse_from([
            "wyr", "install", "s", "plc1", "modbus", "--mode", "process", "--param", "host=h",
            "--param", "port=502",
        ])
        .unwrap();
        match cli.cmd {
            Cmd::Admin(admin::AdminCmd::Install { params, mode, .. }) => {
                assert_eq!(params, ["host=h", "port=502"]);
                assert_eq!(mode.as_deref(), Some("process"));
            }
            other => panic!("{other:?}"),
        }
        assert!(Cli::try_parse_from(["wyr", "audit", "s", "-n", "5"]).is_ok());
        assert!(Cli::try_parse_from(["wyr", "flow", "deploy", "s", "f.json5"]).is_ok());
        assert!(Cli::try_parse_from(["wyr", "flow", "stop", "s", "peak"]).is_ok());
        assert!(Cli::try_parse_from(["wyr", "--tls-key", "k", "links", "s"]).is_ok());
    }

    #[test]
    fn dev_cli_parses() {
        let ok = |args: &[&str]| {
            let mut v = vec!["wyr"];
            v.extend_from_slice(args);
            Cli::try_parse_from(v).map(|c| c.cmd)
        };
        match ok(&["new", "link", "acme", "--proto", "modbus", "--dir", "x"]).unwrap() {
            Cmd::New {
                what: scaffold::NewCmd::Link { name, proto, dir },
            } => {
                assert_eq!(name, "acme");
                assert_eq!(proto, scaffold::Proto::Modbus);
                assert_eq!(dir, PathBuf::from("x"));
            }
            other => panic!("{other:?}"),
        }
        assert!(ok(&["new", "link", "acme", "--proto", "opcua"]).is_err());
        assert!(ok(&["new", "flow", "peak"]).is_ok());
        assert!(ok(&["dev", "--flows", "f", "--site", "s"]).is_ok());
        assert!(ok(&["--key", "admin.key", "dev"]).is_ok());
        assert!(ok(&["token", "wy/s/down/l/p/~set", "--subject", "user:a"]).is_ok());
        assert!(ok(&["sim", "mock", "--points", "500", "--hz", "10", "--depth", "2"]).is_ok());
        assert!(ok(&[
            "sim",
            "mock",
            "--listen",
            "tcp/127.0.0.1:7450",
            "--admin-key",
            "ab"
        ])
        .is_ok());
        assert!(ok(&["record", "wy/s/down/**", "--out", "r.cbor", "--secs", "5"]).is_ok());
        assert!(ok(&["replay", "r.cbor", "--flow", "f.json5", "--speed", "10"]).is_ok());
        assert!(ok(&["replay", "r.cbor"]).is_err(), "--flow is required");
        assert!(matches!(ok(&["tree"]).unwrap(), Cmd::Tree { depth: 3, .. }));
        assert!(matches!(
            ok(&["tree", "wy/s/down/m", "--depth", "1"]).unwrap(),
            Cmd::Tree { depth: 1, .. }
        ));
        assert!(matches!(
            ok(&["watch", "wy/s/**"]).unwrap(),
            Cmd::Sub { .. }
        ));
    }

    #[test]
    fn cli_is_consistent() {
        use clap::CommandFactory;
        Cli::command().debug_assert();
    }

    #[test]
    fn approval_tokens() {
        use base64::Engine;
        let key = ed25519_dalek::SigningKey::from_bytes(&[3; 32]);
        let k = "wy/s/down/l/p/~set";
        let t = approval_token(key.clone(), k, "user:alice", "config", 300).unwrap();
        let raw = base64::engine::general_purpose::STANDARD.decode(t).unwrap();
        let parts = wyrm_core::ptok::split(&raw).unwrap();
        let claims: wyrm_core::PtokClaims = wyrm_core::codec::from_slice(parts.claims).unwrap();
        assert_eq!(claims.sub, "user:alice");
        assert_eq!(claims.site, "s");
        assert_eq!(claims.grants.len(), 1);
        assert_eq!(claims.grants[0].k, k);
        assert!(claims.exp - claims.iat <= 300);
        assert!(approval_token(key.clone(), k, "ai:bot", "config", 300).is_err());
        assert!(approval_token(key.clone(), k, "user:a", "config", 3600).is_err());
        assert!(approval_token(key.clone(), "wy/s/down/**", "user:a", "config", 60).is_err());
        assert!(approval_token(key, k, "user:a", "root", 60).is_err());
    }
}
