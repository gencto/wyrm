//! `wyr` operations on the control plane (`wy/<site>/sys/**`, wyrm-admin).

use crate::{fmt_value, parse_param, Error};
use clap::Subcommand;
use std::collections::BTreeMap;
use wyrm_client::WyrmClient;
use wyrm_core::Value;

#[derive(Subcommand, Debug)]
pub enum AdminCmd {
    /// Links of a site with driver, mode and state.
    Links { site: String },
    /// Install a link (`--param k=v`, repeatable).
    Install {
        site: String,
        id: String,
        driver: String,
        /// embedded | process | external (default: embedded if compiled in).
        #[arg(long)]
        mode: Option<String>,
        #[arg(long = "param")]
        params: Vec<String>,
    },
    /// Start a link.
    Start { site: String, id: String },
    /// Stop a link.
    Stop { site: String, id: String },
    /// Remove a runtime-installed link.
    Remove { site: String, id: String },
    /// Store a link secret; the value is read from stdin (never argv, so it
    /// stays out of shell history). The link sees it on its next start.
    SetSecret {
        site: String,
        id: String,
        name: String,
    },
    /// Delete a link secret.
    DeleteSecret {
        site: String,
        id: String,
        name: String,
    },
    /// Sessions with unknown certificates.
    Quarantine { site: String },
    /// Admit a quarantined certificate as an external link.
    Approve {
        site: String,
        cn: String,
        #[arg(long)]
        driver: Option<String>,
    },
    /// Refuse a quarantined certificate for good.
    Reject { site: String, cn: String },
    /// Last audit records.
    Audit {
        site: String,
        #[arg(short, default_value_t = 50)]
        n: u64,
    },
}

fn sys(site: &str, rest: &str) -> String {
    if rest.is_empty() {
        format!("wy/{site}/sys")
    } else {
        format!("wy/{site}/sys/{rest}")
    }
}

impl AdminCmd {
    /// Site of the command (tokens are minted for it).
    pub fn site(&self) -> &str {
        match self {
            AdminCmd::Links { site }
            | AdminCmd::Install { site, .. }
            | AdminCmd::Start { site, .. }
            | AdminCmd::Stop { site, .. }
            | AdminCmd::Remove { site, .. }
            | AdminCmd::SetSecret { site, .. }
            | AdminCmd::DeleteSecret { site, .. }
            | AdminCmd::Quarantine { site }
            | AdminCmd::Approve { site, .. }
            | AdminCmd::Reject { site, .. }
            | AdminCmd::Audit { site, .. } => site,
        }
    }
}

fn attr(m: &wyrm_core::NodeMeta, k: &str) -> String {
    m.attr_value(k)
        .map(|v| match v {
            Value::Str(s) => s.clone(),
            v => fmt_value(v),
        })
        .unwrap_or_else(|| "-".into())
}

/// Last stored value of `node` (storage replies, no status attachment).
async fn last_value(c: &WyrmClient, node: &str) -> Option<Value> {
    let r = c.session().get(format!("{node}/~val")).await.ok()?;
    let reply = r.recv_async().await.ok()?;
    let s = reply.result().ok()?;
    wyrm_core::codec::from_slice::<wyrm_core::Sample>(&s.payload().to_bytes())
        .ok()
        .map(|s| s.v)
}

/// Enum leaf as its name (`state` → `connected`).
async fn enum_name(c: &WyrmClient, node: &str) -> String {
    let Some(v) = last_value(c, node).await else {
        return "?".into();
    };
    let names = c.meta(node).await.ok().and_then(|m| m.enum_values);
    match (v, names) {
        (Value::UInt(i), Some(n)) => n.get(i as usize).cloned().unwrap_or_else(|| i.to_string()),
        (v, _) => fmt_value(&v),
    }
}

async fn invoke(
    c: &WyrmClient,
    node: &str,
    action: &str,
    args: BTreeMap<String, Value>,
) -> Result<(), Error> {
    match c.invoke_one(node, action, Value::Map(args)).await? {
        Some(Value::Map(m)) if !m.is_empty() => {
            for (k, v) in m {
                let v = match v {
                    Value::Str(s) => s,
                    v => fmt_value(&v),
                };
                out!("{k}: {v}");
            }
        }
        Some(Value::Map(_)) | None => out!("ok"),
        Some(v) => out!("{}", fmt_value(&v)),
    }
    Ok(())
}

pub async fn run(c: &WyrmClient, cmd: AdminCmd) -> Result<(), Error> {
    match cmd {
        AdminCmd::Links { site } => {
            let root = sys(&site, "links");
            for child in c.children(&root).await? {
                let node = format!("{root}/{}", child.name);
                let m = c.meta(&node).await?;
                let state = enum_name(c, &format!("{node}/state")).await;
                out!(
                    "{:<20} {:<10} {:<9} {state}",
                    child.name,
                    attr(&m, "driver"),
                    attr(&m, "mode")
                );
            }
            Ok(())
        }
        AdminCmd::Install {
            site,
            id,
            driver,
            mode,
            params,
        } => {
            let mut p = BTreeMap::new();
            for kv in &params {
                let (k, v) = parse_param(kv)?;
                p.insert(k, v);
            }
            let mut args = BTreeMap::new();
            args.insert("id".to_owned(), Value::Str(id));
            args.insert("driver".to_owned(), Value::Str(driver));
            if let Some(m) = mode {
                args.insert("mode".to_owned(), Value::Str(m));
            }
            args.insert("params".to_owned(), Value::Map(p));
            invoke(c, &sys(&site, "links"), "install", args).await
        }
        AdminCmd::Start { site, id } => {
            invoke(
                c,
                &sys(&site, &format!("links/{id}")),
                "start",
                BTreeMap::new(),
            )
            .await
        }
        AdminCmd::Stop { site, id } => {
            invoke(
                c,
                &sys(&site, &format!("links/{id}")),
                "stop",
                BTreeMap::new(),
            )
            .await
        }
        AdminCmd::Remove { site, id } => {
            invoke(
                c,
                &sys(&site, &format!("links/{id}")),
                "remove",
                BTreeMap::new(),
            )
            .await
        }
        AdminCmd::SetSecret { site, id, name } => {
            let mut value = zeroize::Zeroizing::new(String::new());
            std::io::stdin().read_line(&mut value)?;
            let value = value.trim_end_matches(['\r', '\n']);
            if value.is_empty() {
                return Err("empty secret on stdin".into());
            }
            let mut args = BTreeMap::new();
            args.insert("name".to_owned(), Value::Str(name));
            args.insert("value".to_owned(), Value::Bytes(value.as_bytes().to_vec()));
            invoke(c, &sys(&site, &format!("links/{id}")), "set_secret", args).await
        }
        AdminCmd::DeleteSecret { site, id, name } => {
            let mut args = BTreeMap::new();
            args.insert("name".to_owned(), Value::Str(name));
            invoke(
                c,
                &sys(&site, &format!("links/{id}")),
                "delete_secret",
                args,
            )
            .await
        }
        AdminCmd::Quarantine { site } => {
            let root = sys(&site, "quarantine");
            for child in c.children(&root).await? {
                let m = c.meta(&format!("{root}/{}", child.name)).await?;
                out!(
                    "{:<24} attempts={} first_seen={} last_seen={}",
                    child.name,
                    attr(&m, "attempts"),
                    attr(&m, "first_seen"),
                    attr(&m, "last_seen")
                );
            }
            Ok(())
        }
        AdminCmd::Approve { site, cn, driver } => {
            let mut args = BTreeMap::new();
            if let Some(d) = driver {
                args.insert("driver".to_owned(), Value::Str(d));
            }
            invoke(c, &sys(&site, &format!("quarantine/{cn}")), "approve", args).await
        }
        AdminCmd::Reject { site, cn } => {
            invoke(
                c,
                &sys(&site, &format!("quarantine/{cn}")),
                "reject",
                BTreeMap::new(),
            )
            .await
        }
        AdminCmd::Audit { site, n } => {
            let mut args = BTreeMap::new();
            args.insert("n".to_owned(), Value::UInt(n));
            match c
                .invoke_one(&sys(&site, "audit"), "tail", Value::Map(args))
                .await?
            {
                Some(Value::Array(recs)) => {
                    for r in recs {
                        let Value::Map(m) = r else { continue };
                        let get = |k: &str| match m.get(k) {
                            Some(Value::Str(s)) => s.clone(),
                            Some(v) => fmt_value(v),
                            None => String::new(),
                        };
                        out!(
                            "{} {} {} {} status={} {}",
                            get("t"),
                            get("sub"),
                            get("op"),
                            get("key"),
                            get("status"),
                            get("detail")
                        );
                    }
                }
                other => out!("{}", other.map(|v| fmt_value(&v)).unwrap_or_default()),
            }
            Ok(())
        }
    }
}
