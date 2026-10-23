//! `wyr flow …`: the data-flow engine under `wy/<site>/dataflows` (spec 06).

use crate::{admin::last_value, fmt_value, Error};
use clap::Subcommand;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use wyrm_client::WyrmClient;
use wyrm_core::{Attachment, StatusGroup, Value};

#[derive(Subcommand, Debug)]
pub enum FlowCmd {
    /// Flows of a site with state and version.
    List { site: String },
    /// Definition (`~def`) and state of a flow.
    Show { site: String, id: String },
    /// Compile a definition (JSON or JSON5 file) without deploying it.
    Validate { site: String, file: PathBuf },
    /// Deploy a definition (JSON or JSON5 file); signs a proof per command target.
    Deploy { site: String, file: PathBuf },
    /// Start a flow.
    Start { site: String, id: String },
    /// Stop a flow (node state is kept).
    Stop { site: String, id: String },
    /// Restart a flow from its saved state.
    Reload { site: String, id: String },
    /// Stop a flow and delete its definition.
    Remove { site: String, id: String },
}

impl FlowCmd {
    /// Site of the command (tokens are minted for it).
    pub fn site(&self) -> &str {
        match self {
            FlowCmd::List { site }
            | FlowCmd::Show { site, .. }
            | FlowCmd::Validate { site, .. }
            | FlowCmd::Deploy { site, .. }
            | FlowCmd::Start { site, .. }
            | FlowCmd::Stop { site, .. }
            | FlowCmd::Reload { site, .. }
            | FlowCmd::Remove { site, .. } => site,
        }
    }
}

pub fn root(site: &str) -> String {
    format!("wy/{site}/dataflows")
}

/// JSON value → wire value (same mapping as `wyrmd`).
pub fn json_to_value(j: &serde_json::Value) -> Value {
    match j {
        serde_json::Value::Null => Value::Null,
        serde_json::Value::Bool(b) => Value::Bool(*b),
        serde_json::Value::Number(n) => {
            if let Some(u) = n.as_u64() {
                Value::UInt(u)
            } else if let Some(i) = n.as_i64() {
                Value::Int(i)
            } else {
                Value::Float(n.as_f64().unwrap_or(f64::NAN))
            }
        }
        serde_json::Value::String(s) => Value::Str(s.clone()),
        serde_json::Value::Array(a) => Value::Array(a.iter().map(json_to_value).collect()),
        serde_json::Value::Object(o) => Value::Map(
            o.iter()
                .map(|(k, v)| (k.clone(), json_to_value(v)))
                .collect(),
        ),
    }
}

/// Definition text (JSON is a subset of JSON5) → wire value.
pub fn parse_def(text: &str) -> Result<Value, Error> {
    let j: serde_json::Value = json5::from_str(text)?;
    match j {
        serde_json::Value::Object(_) => Ok(json_to_value(&j)),
        _ => Err("flow definition must be an object".into()),
    }
}

fn read_def(path: &Path) -> Result<Value, Error> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    parse_def(&text).map_err(|e| format!("{}: {e}", path.display()).into())
}

/// `deploy` arguments: `{def, proofs}` with one proof per command target.
/// Fails on the first target `proof` cannot sign for.
pub fn deploy_args(
    def: Value,
    site: &str,
    proof: &dyn Fn(&str) -> Option<Vec<u8>>,
) -> Result<Value, Error> {
    let targets =
        wyrm_flow::command_targets(&def, site).map_err(|e| format!("flow definition: {e}"))?;
    let mut proofs = BTreeMap::new();
    for t in targets {
        let Some(tok) = proof(&t) else {
            return Err(format!(
                "cannot sign a proof for command target {t} (pass --key with an admin key)"
            )
            .into());
        };
        proofs.insert(t, Value::Bytes(tok));
    }
    let mut m = BTreeMap::new();
    m.insert("def".to_owned(), def);
    m.insert("proofs".to_owned(), Value::Map(proofs));
    Ok(Value::Map(m))
}

/// Engine state code (`~val.state`) → name.
fn state_name(v: Option<&Value>) -> String {
    match v {
        Some(Value::UInt(0)) => "running".into(),
        Some(Value::UInt(1)) => "stopped".into(),
        Some(Value::UInt(2)) => "error".into(),
        Some(v) => fmt_value(v),
        None => "?".into(),
    }
}

/// `state version [error]` of a flow from its `~val`.
async fn state_line(c: &WyrmClient, node: &str) -> String {
    let Some(Value::Map(m)) = last_value(c, node).await else {
        return "?".into();
    };
    let mut s = state_name(m.get("state"));
    if let Some(v) = m.get("version") {
        s.push_str(&format!(" v{}", fmt_value(v)));
    }
    if let Some(Value::Str(e)) = m.get("error") {
        s.push_str(&format!("  {e}"));
    }
    s
}

/// Compile `def` with the engine's `validate` action (nothing is deployed).
pub(crate) async fn validate(c: &WyrmClient, site: &str, def: Value) -> Result<(), Error> {
    let mut args = BTreeMap::new();
    args.insert("def".to_owned(), def);
    match c
        .invoke_one(&root(site), "validate", Value::Map(args))
        .await?
    {
        Some(Value::Map(m)) if m.get("ok") == Some(&Value::Bool(true)) => Ok(()),
        Some(Value::Map(m)) => {
            let e = match m.get("error") {
                Some(Value::Str(s)) => s.clone(),
                Some(v) => fmt_value(v),
                None => "invalid".into(),
            };
            Err(format!("invalid: {e}").into())
        }
        other => Err(format!(
            "validate: unexpected reply {}",
            other.map(|v| fmt_value(&v)).unwrap_or_default()
        )
        .into()),
    }
}

/// `get <node>/~def` with a `ptok` (restricted nodes need `list`).
pub(crate) async fn get_def(c: &WyrmClient, node: &str) -> Result<Value, Error> {
    let key = format!("{node}/~def");
    let att = Attachment {
        ptok: c.proof(&key),
        ..Default::default()
    };
    let rx = c
        .session()
        .get(&key)
        .attachment(wyrm_core::codec::to_vec(&att)?)
        .await?;
    let reply = rx
        .recv_async()
        .await
        .map_err(|_| format!("{key}: no reply"))?;
    let s = reply.result().map_err(|e| {
        format!(
            "{key}: {}",
            String::from_utf8_lossy(&e.payload().to_bytes())
        )
    })?;
    let att: Attachment = match s.attachment() {
        Some(a) => wyrm_core::codec::from_slice(&a.to_bytes())?,
        None => Attachment::default(),
    };
    if let Some(st) = att.status.filter(|s| s.group() == StatusGroup::Error) {
        return Err(format!("{key}: {st:?} {}", att.err.unwrap_or_default()).into());
    }
    Ok(wyrm_core::codec::from_slice(&s.payload().to_bytes())?)
}

async fn invoke(c: &WyrmClient, node: &str, action: &str, args: Value) -> Result<(), Error> {
    match c.invoke_one(node, action, args).await? {
        Some(Value::Map(m)) if m.is_empty() => out!("ok"),
        None => out!("ok"),
        Some(v) => out!("{}", fmt_value(&v)),
    }
    Ok(())
}

fn no_args() -> Value {
    Value::Map(BTreeMap::new())
}

pub async fn run(c: &WyrmClient, cmd: FlowCmd) -> Result<(), Error> {
    match cmd {
        FlowCmd::List { site } => {
            let root = root(&site);
            for child in c.children(&root).await? {
                let state = state_line(c, &format!("{root}/{}", child.name)).await;
                out!("{:<24} {state}", child.name);
            }
            Ok(())
        }
        FlowCmd::Show { site, id } => {
            let node = format!("{}/{id}", root(&site));
            out!("state  {}", state_line(c, &node).await);
            out!("def    {}", fmt_value(&get_def(c, &node).await?));
            Ok(())
        }
        FlowCmd::Validate { site, file } => {
            validate(c, &site, read_def(&file)?).await?;
            out!("ok");
            Ok(())
        }
        FlowCmd::Deploy { site, file } => {
            let args = deploy_args(read_def(&file)?, &site, &|k| c.proof(k))?;
            invoke(c, &root(&site), "deploy", args).await
        }
        FlowCmd::Start { site, id } => {
            invoke(c, &format!("{}/{id}", root(&site)), "start", no_args()).await
        }
        FlowCmd::Stop { site, id } => {
            invoke(c, &format!("{}/{id}", root(&site)), "stop", no_args()).await
        }
        FlowCmd::Reload { site, id } => {
            invoke(c, &format!("{}/{id}", root(&site)), "reload", no_args()).await
        }
        FlowCmd::Remove { site, id } => {
            invoke(c, &format!("{}/{id}", root(&site)), "remove", no_args()).await
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const DEF: &str = r#"{
        // JSON5: comments, trailing commas, unquoted keys
        id: "peak",
        version: 2,
        nodes: {
            a: { type: "subscribe", key: "downstream/mock/p0" },
            alarm: { type: "alarm", high: 30.5, low: -1 },
            shed: { type: "invoke", path: "downstream/mock", action: "reset" },
            out: { type: "set", path: "wy/s/downstream/mock/sp" },
        },
        edges: [],
    }"#;

    #[test]
    fn json5_to_value() {
        let v = parse_def(DEF).unwrap();
        let Value::Map(m) = &v else { panic!("{v:?}") };
        assert_eq!(m["id"], Value::Str("peak".into()));
        assert_eq!(m["version"], Value::UInt(2));
        assert_eq!(m["edges"], Value::Array(vec![]));
        let Value::Map(nodes) = &m["nodes"] else {
            panic!()
        };
        let Value::Map(alarm) = &nodes["alarm"] else {
            panic!()
        };
        assert_eq!(alarm["high"], Value::Float(30.5));
        assert_eq!(alarm["low"], Value::Int(-1));
        // plain JSON too
        assert_eq!(
            parse_def(r#"{"a": null, "b": [true, 1.0]}"#).unwrap(),
            Value::Map(BTreeMap::from([
                ("a".into(), Value::Null),
                (
                    "b".into(),
                    Value::Array(vec![Value::Bool(true), Value::Float(1.0)])
                ),
            ]))
        );
        assert!(parse_def("[1]").is_err());
        assert!(parse_def("{ broken").is_err());
    }

    #[test]
    fn proofs_per_target() {
        let def = parse_def(DEF).unwrap();
        let args = deploy_args(def.clone(), "s", &|k| Some(k.as_bytes().to_vec())).unwrap();
        let Value::Map(m) = args else { panic!() };
        assert_eq!(m["def"], def);
        let Value::Map(p) = &m["proofs"] else {
            panic!()
        };
        let keys: Vec<&str> = p.keys().map(String::as_str).collect();
        assert_eq!(
            keys,
            [
                "wy/s/downstream/mock/sp/~set",
                "wy/s/downstream/mock/~act/reset"
            ]
        );
        assert_eq!(
            p["wy/s/downstream/mock/~act/reset"],
            Value::Bytes(b"wy/s/downstream/mock/~act/reset".to_vec())
        );
    }

    #[test]
    fn missing_proof_names_the_target() {
        let def = parse_def(DEF).unwrap();
        let only_set = |k: &str| k.ends_with("~set").then(|| vec![1]);
        let e = deploy_args(def.clone(), "s", &only_set).unwrap_err();
        assert!(
            e.to_string().contains("wy/s/downstream/mock/~act/reset"),
            "{e}"
        );
        // no command targets → no proofs needed
        let plain = parse_def(r#"{id: "x", nodes: {a: {type: "subscribe", key: "k"}}}"#).unwrap();
        let Value::Map(m) = deploy_args(plain, "s", &|_| None).unwrap() else {
            panic!()
        };
        assert_eq!(m["proofs"], Value::Map(BTreeMap::new()));
    }
}
