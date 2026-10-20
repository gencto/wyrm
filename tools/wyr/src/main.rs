//! `wyr` — WYRM command line. Node keys are full keys without suffix:
//! `wyr list wy/local/down/mock/g0`.

/// `println!` that exits quietly when stdout is closed (`wyr … | head`).
macro_rules! out {
    ($($t:tt)*) => {{
        use std::io::Write as _;
        if writeln!(std::io::stdout(), $($t)*).is_err() {
            std::process::exit(0);
        }
    }};
}

mod bench;

use clap::{Parser, Subcommand};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
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
    /// Live values for a node pattern (`wy/local/down/mock/**`).
    Sub {
        pattern: String,
        /// QoS 2/3: publisher history first, then live, with gap recovery.
        #[arg(long)]
        reliable: bool,
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
    /// Create an admin signing key (hex seed, mode 0600) and print the public key.
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
    if let Cmd::Keygen { out } = &cli.cmd {
        return keygen(out);
    }
    let client = connect(&cli).await?;
    match cli.cmd {
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
            for a in args {
                let (k, v) = a
                    .split_once('=')
                    .ok_or_else(|| format!("argument {a:?} is not name=value"))?;
                map.insert(k.to_owned(), parse_value(v));
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
        Cmd::Keygen { .. } => unreachable!(),
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

async fn connect(cli: &Cli) -> Result<Ctx, Error> {
    let mut zc = zenoh::Config::default();
    zc.insert_json5("mode", r#""client""#)?;
    zc.insert_json5("connect/endpoints", &format!("[\"{}\"]", cli.connect))?;
    zc.insert_json5("scouting/multicast/enabled", "false")?;
    let session = zenoh::open(zc).await?;
    Ok(Ctx {
        inner: WyrmClient::new(session).with_timeout(Duration::from_secs(cli.timeout)),
    })
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
}
