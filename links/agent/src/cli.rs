//! `wyrm-agent`: the operator's (or an AI assistant's) command line over a gateway (ADR 0033).
//!
//! It logs in as a gateway user and works through the gateway's WebSocket: the user's role
//! decides every read and write, and the gateway reaches the sites below it (ADR 0007, 0018),
//! so one gateway drives a chain of brokers. Every answer is JSON, one object per line.
//!
//! `run <plan.json>` checks a plan of steps against the live `~meta` (the action exists, its
//! arguments fit, the value fits the point) and prints what it would do; `--apply` runs the
//! steps in order and stops at the first that fails.

use std::collections::BTreeMap;
use std::time::Duration;

use serde_json::{json, Value as Json};
use wyrm_core::{NodeMeta, Value};
use wyrm_gateway_client::{Conn, Event, Gateway};
use wyrm_mcp::check;
use wyrm_mcp::json::{json_to_value, meta_to_json, value_to_json};

pub type Result<T> = std::result::Result<T, String>;

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// Log in and open one WebSocket.
pub async fn connect(url: &str, user: &str, password: &str) -> Result<Conn> {
    let gw = Gateway::login(url, user, password).await.map_err(err)?;
    gw.connect().await.map_err(err)
}

/// `~meta` of `key` as JSON.
pub async fn meta(c: &Conn, key: &str) -> Result<Json> {
    Ok(meta_to_json(&c.meta(key).await.map_err(err)?))
}

/// The tree below `key`, `depth` levels: one line per node.
pub async fn tree(c: &Conn, key: &str, depth: usize) -> Result<Vec<Json>> {
    let mut out = Vec::new();
    let mut level = vec![key.trim_end_matches('/').to_owned()];
    for _ in 0..depth {
        let mut next = Vec::new();
        for k in level {
            for (name, m) in c.children(&k).await.map_err(err)? {
                let child = format!("{k}/{name}");
                let mut line = json!({ "key": child });
                if let Some(t) = m.ty {
                    line["type"] = json!(t.name());
                }
                if let Some(wyrm_core::meta::TextOrCode::Text(u)) = &m.unit {
                    line["unit"] = json!(u);
                }
                if let Some(w) = m.writable {
                    line["writable"] = json!(w.name());
                }
                if m.ty.is_none() {
                    next.push(child);
                }
                out.push(line);
            }
        }
        level = next;
        if level.is_empty() {
            break;
        }
    }
    Ok(out)
}

/// The current value of `key` (the first sample of a subscription), within `wait`.
pub async fn get(c: &Conn, key: &str, wait: Duration) -> Result<Json> {
    let mut s = c.subscribe(key).await.map_err(err)?;
    let r = tokio::time::timeout(wait, async {
        loop {
            match s.next().await {
                Some(Event::Sample { v, q, t, .. }) => {
                    break Ok(json!({ "key": key, "v": value_to_json(&v), "q": q, "t": t }))
                }
                Some(Event::Closed) | None => break Err(format!("{key}: the stream ended")),
                Some(_) => {}
            }
        }
    })
    .await
    .unwrap_or_else(|_| Err(format!("{key}: no value within {} s", wait.as_secs_f32())));
    let _ = c.unsubscribe(s.id).await;
    r
}

/// Samples of `pattern` for `seconds`.
pub async fn watch(c: &Conn, pattern: &str, seconds: f64) -> Result<Vec<Json>> {
    let mut s = c.subscribe(pattern).await.map_err(err)?;
    let mut out = Vec::new();
    let end = tokio::time::Instant::now() + Duration::from_secs_f64(seconds.max(0.0));
    while let Ok(Some(e)) = tokio::time::timeout_at(end, s.next()).await {
        if let Event::Sample { key, v, q, t } = e {
            out.push(json!({ "key": key, "v": value_to_json(&v), "q": q, "t": t }));
        }
    }
    let _ = c.unsubscribe(s.id).await;
    Ok(out)
}

/// Recorded values of a point (`~val?history=`, spec 01).
pub async fn history(c: &Conn, key: &str, args: Value) -> Result<Json> {
    let v = c
        .request("history", key, vec![("args", args)])
        .await
        .map_err(err)?;
    Ok(v.map_or(Json::Null, |v| value_to_json(&v)))
}

pub async fn set(c: &Conn, key: &str, v: Value) -> Result<Json> {
    c.set(key, v).await.map_err(err)?;
    Ok(json!({ "ok": true, "key": key }))
}

pub async fn invoke(c: &Conn, key: &str, action: &str, args: Value) -> Result<Json> {
    let r = c.invoke(key, action, args).await.map_err(err)?;
    Ok(
        json!({ "ok": true, "key": key, "action": action, "result": r.map_or(Json::Null, |v| value_to_json(&v)) }),
    )
}

// ---------- plans ----------

/// One step of a plan (`run`).
#[derive(Debug, Clone, PartialEq)]
pub enum Step {
    /// Run an action; skipped when `unless` already exists, and done when it is refused with
    /// a message holding `ok_if_error` (what was asked is already so: "is watched").
    Invoke {
        key: String,
        action: String,
        args: Json,
        unless: Option<String>,
        ok_if_error: Option<String>,
    },
    Set {
        key: String,
        value: Json,
    },
    /// Deploy a flow on `<site>/dataflows`; the version goes one above the current one.
    Deploy {
        dataflows: String,
        def: Json,
    },
    /// Wait until the node exists.
    Wait {
        key: String,
        timeout_s: f64,
    },
    /// Wait until the point's value meets the test.
    Expect {
        key: String,
        test: Test,
        timeout_s: f64,
    },
    Sleep(f64),
}

#[derive(Debug, Clone, PartialEq)]
pub enum Test {
    /// Any value at all.
    Any,
    Equals(Json),
    /// A number in `[min, max]`.
    Range(Option<f64>, Option<f64>),
    /// Two different values seen.
    Changes,
}

fn text<'a>(o: &'a serde_json::Map<String, Json>, k: &str) -> Result<&'a str> {
    o.get(k)
        .and_then(Json::as_str)
        .ok_or_else(|| format!("`{k}` (text) is required"))
}

fn secs(o: &serde_json::Map<String, Json>, d: f64) -> f64 {
    o.get("timeout_s")
        .and_then(Json::as_f64)
        .unwrap_or(d)
        .clamp(0.0, 600.0)
}

/// The steps of a plan file: `{"steps": [...]}` or a bare list.
pub fn parse_plan(j: &Json) -> Result<Vec<Step>> {
    let list = match j {
        Json::Array(a) => a,
        Json::Object(o) => o
            .get("steps")
            .and_then(Json::as_array)
            .ok_or("a plan is {\"steps\": [...]}")?,
        _ => return Err("a plan is {\"steps\": [...]}".into()),
    };
    if list.len() > 200 {
        return Err("a plan has at most 200 steps".into());
    }
    list.iter()
        .enumerate()
        .map(|(i, s)| parse_step(s).map_err(|e| format!("step {}: {e}", i + 1)))
        .collect()
}

fn parse_step(s: &Json) -> Result<Step> {
    let o = s.as_object().ok_or("a step is an object")?;
    if let Some(k) = o.get("invoke") {
        return Ok(Step::Invoke {
            key: k.as_str().ok_or("`invoke`: a node key")?.to_owned(),
            action: text(o, "action")?.to_owned(),
            args: o.get("args").cloned().unwrap_or(json!({})),
            unless: o.get("unless").and_then(Json::as_str).map(str::to_owned),
            ok_if_error: o
                .get("ok_if_error")
                .and_then(Json::as_str)
                .filter(|s| !s.is_empty())
                .map(str::to_owned),
        });
    }
    if let Some(k) = o.get("set") {
        return Ok(Step::Set {
            key: k.as_str().ok_or("`set`: a node key")?.to_owned(),
            value: o.get("value").cloned().ok_or("`value` is required")?,
        });
    }
    if let Some(k) = o.get("deploy") {
        let def = o.get("def").cloned().ok_or("`def` is required")?;
        def.get("id")
            .and_then(Json::as_str)
            .ok_or("`def.id` is required")?;
        return Ok(Step::Deploy {
            dataflows: k
                .as_str()
                .ok_or("`deploy`: wy/<site>/dataflows")?
                .to_owned(),
            def,
        });
    }
    if let Some(k) = o.get("wait") {
        return Ok(Step::Wait {
            key: k.as_str().ok_or("`wait`: a node key")?.to_owned(),
            timeout_s: secs(o, 10.0),
        });
    }
    if let Some(k) = o.get("expect") {
        let test = if let Some(v) = o.get("equals") {
            Test::Equals(v.clone())
        } else if o.get("changes").and_then(Json::as_bool) == Some(true) {
            Test::Changes
        } else if o.contains_key("min") || o.contains_key("max") {
            Test::Range(
                o.get("min").and_then(Json::as_f64),
                o.get("max").and_then(Json::as_f64),
            )
        } else {
            Test::Any
        };
        return Ok(Step::Expect {
            key: k.as_str().ok_or("`expect`: a node key")?.to_owned(),
            test,
            timeout_s: secs(o, 10.0),
        });
    }
    if let Some(s) = o.get("sleep_s").and_then(Json::as_f64) {
        return Ok(Step::Sleep(s.clamp(0.0, 600.0)));
    }
    Err("one of invoke, set, deploy, wait, expect, sleep_s".into())
}

/// A node's `~meta`, or `None` when it does not exist (yet).
async fn meta_of(c: &Conn, key: &str) -> Option<NodeMeta> {
    c.meta(key).await.ok().filter(|m| m != &NodeMeta::default())
}

/// The check of one step against the live tree, without sending anything.
pub async fn check_step(c: &Conn, step: &Step) -> Json {
    match step {
        Step::Invoke {
            key,
            action,
            args,
            unless,
            ..
        } => {
            if let Some(u) = unless {
                if meta_of(c, u).await.is_some() {
                    return json!({ "step": "invoke", "key": key, "action": action, "check": "skip", "why": format!("{u} exists") });
                }
            }
            let Some(m) = meta_of(c, key).await else {
                return json!({ "step": "invoke", "key": key, "action": action, "check": "later", "why": "the node does not exist yet: checked when it runs" });
            };
            match invoke_args(&m, action, args) {
                Ok((level, _)) => {
                    json!({ "step": "invoke", "key": key, "action": action, "check": "ok", "level": level })
                }
                Err(e) => {
                    json!({ "step": "invoke", "key": key, "action": action, "check": "error", "error": e })
                }
            }
        }
        Step::Set { key, value } => match meta_of(c, key).await {
            None => {
                json!({ "step": "set", "key": key, "check": "later", "why": "the node does not exist yet" })
            }
            Some(m) => match set_value(&m, value) {
                Ok(_) => json!({ "step": "set", "key": key, "check": "ok" }),
                Err(e) => json!({ "step": "set", "key": key, "check": "error", "error": e }),
            },
        },
        Step::Deploy { dataflows, def } => {
            let id = def["id"].as_str().unwrap_or_default();
            match json_to_value(def) {
                Err(e) => json!({ "step": "deploy", "flow": id, "check": "error", "error": e }),
                Ok(v) => match c.invoke(dataflows, "validate", map([("def", v)])).await {
                    Ok(Some(r)) => {
                        let r = value_to_json(&r);
                        let ok = r["ok"] == json!(true);
                        json!({ "step": "deploy", "flow": id, "check": if ok { "ok" } else { "error" }, "validate": r })
                    }
                    Ok(None) => json!({ "step": "deploy", "flow": id, "check": "ok" }),
                    Err(e) => {
                        json!({ "step": "deploy", "flow": id, "check": "error", "error": e.to_string() })
                    }
                },
            }
        }
        Step::Wait { key, .. } => json!({ "step": "wait", "key": key, "check": "ok" }),
        Step::Expect { key, .. } => json!({ "step": "expect", "key": key, "check": "ok" }),
        Step::Sleep(s) => json!({ "step": "sleep", "seconds": s, "check": "ok" }),
    }
}

fn map<const N: usize>(kv: [(&str, Value); N]) -> Value {
    Value::Map(kv.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

/// The action's arguments as its schema takes them, and its level.
fn invoke_args(m: &NodeMeta, action: &str, args: &Json) -> Result<(&'static str, Value)> {
    let level = check::action_level(m, action)?;
    let act = m
        .actions
        .as_ref()
        .and_then(|a| a.get(action))
        .cloned()
        .unwrap_or_default();
    let given: BTreeMap<String, Value> = match args {
        Json::Null => BTreeMap::new(),
        Json::Object(o) => o
            .iter()
            .map(|(k, v)| json_to_value(v).map(|v| (k.clone(), v)))
            .collect::<Result<_>>()?,
        _ => return Err("`args` must be an object".into()),
    };
    let args = check::prepare_args(&act.params, given)?;
    Ok((level.name(), Value::Map(args)))
}

fn set_value(m: &NodeMeta, value: &Json) -> Result<Value> {
    check::set_level(m)?;
    let v = check::coerce_enum(m.ty, m.enum_values.as_deref(), json_to_value(value)?);
    check::validate_value(m, &v)?;
    Ok(v)
}

/// Run one step; `Err` stops the plan.
pub async fn run_step(c: &Conn, step: &Step) -> Result<Json> {
    match step {
        Step::Invoke {
            key,
            action,
            args,
            unless,
            ok_if_error,
        } => {
            if let Some(u) = unless {
                if meta_of(c, u).await.is_some() {
                    return Ok(
                        json!({ "step": "invoke", "key": key, "action": action, "done": "skipped", "why": format!("{u} exists") }),
                    );
                }
            }
            let m = meta_of(c, key)
                .await
                .ok_or_else(|| format!("{key}: no such node"))?;
            let (_, args) = invoke_args(&m, action, args)?;
            match invoke(c, key, action, args).await {
                Err(e) if ok_if_error.as_ref().is_some_and(|o| e.contains(o.as_str())) => Ok(
                    json!({ "step": "invoke", "key": key, "action": action, "done": "already", "why": e }),
                ),
                r => r,
            }
        }
        Step::Set { key, value } => {
            let m = meta_of(c, key)
                .await
                .ok_or_else(|| format!("{key}: no such node"))?;
            set(c, key, set_value(&m, value)?).await
        }
        Step::Deploy { dataflows, def } => {
            let id = def["id"].as_str().unwrap_or_default().to_owned();
            // one above what runs, so the same plan deploys again
            let current = get(c, &format!("{dataflows}/{id}"), Duration::from_secs(2))
                .await
                .ok()
                .and_then(|j| j["v"]["version"].as_u64())
                .unwrap_or(0);
            let mut def = def.clone();
            def["version"] = json!(current + 1);
            let v = json_to_value(&def)?;
            c.invoke(dataflows, "deploy", map([("def", v)]))
                .await
                .map_err(err)?;
            Ok(json!({ "step": "deploy", "flow": id, "version": current + 1, "done": "ok" }))
        }
        Step::Wait { key, timeout_s } => {
            let end = tokio::time::Instant::now() + Duration::from_secs_f64(*timeout_s);
            loop {
                if meta_of(c, key).await.is_some() {
                    return Ok(json!({ "step": "wait", "key": key, "done": "ok" }));
                }
                if tokio::time::Instant::now() >= end {
                    return Err(format!("{key}: not there after {timeout_s} s"));
                }
                tokio::time::sleep(Duration::from_millis(250)).await;
            }
        }
        Step::Expect {
            key,
            test,
            timeout_s,
        } => expect(c, key, test, *timeout_s).await,
        Step::Sleep(s) => {
            tokio::time::sleep(Duration::from_secs_f64(*s)).await;
            Ok(json!({ "step": "sleep", "seconds": s, "done": "ok" }))
        }
    }
}

async fn expect(c: &Conn, key: &str, test: &Test, timeout_s: f64) -> Result<Json> {
    let mut s = c.subscribe(key).await.map_err(err)?;
    let end = tokio::time::Instant::now() + Duration::from_secs_f64(timeout_s);
    let mut first: Option<Value> = None;
    let mut last = Json::Null;
    let r = loop {
        let e = match tokio::time::timeout_at(end, s.next()).await {
            Ok(Some(e)) => e,
            Ok(None) => break Err(format!("{key}: the stream ended")),
            Err(_) => {
                break Err(format!(
                    "{key}: not as expected after {timeout_s} s (last {last})"
                ))
            }
        };
        let Event::Sample { v, q, .. } = e else {
            continue;
        };
        last = value_to_json(&v);
        let pass = match test {
            Test::Any => true,
            Test::Equals(want) => {
                &last == want || last.as_f64().is_some_and(|x| Some(x) == want.as_f64())
            }
            Test::Range(lo, hi) => last
                .as_f64()
                .is_some_and(|x| lo.is_none_or(|l| x >= l) && hi.is_none_or(|h| x <= h)),
            Test::Changes => match &first {
                None => {
                    first = Some(v.clone());
                    false
                }
                Some(f) => f != &v,
            },
        };
        if pass {
            break Ok(json!({ "step": "expect", "key": key, "done": "ok", "v": last, "q": q }));
        }
    };
    let _ = c.unsubscribe(s.id).await;
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plans_parse_and_refuse() {
        let p = parse_plan(&json!({"steps": [
            {"invoke": "wy/s/downstream/m/c", "action": "add_device", "args": {"name": "d"}, "unless": "wy/s/downstream/m/c/d"},
            {"wait": "wy/s/downstream/m/c/d", "timeout_s": 5},
            {"set": "wy/s/downstream/m/c/d/sp", "value": 21.5},
            {"deploy": "wy/s/dataflows", "def": {"id": "f", "nodes": {}, "edges": []}},
            {"expect": "wy/s/dataflows/f/nodes/x", "min": 1, "max": 9},
            {"expect": "k", "changes": true},
            {"sleep_s": 1}
        ]}))
        .unwrap();
        assert_eq!(p.len(), 7);
        assert!(matches!(
            &p[0],
            Step::Invoke {
                unless: Some(_),
                ..
            }
        ));
        assert_eq!(
            p[4],
            Step::Expect {
                key: "wy/s/dataflows/f/nodes/x".into(),
                test: Test::Range(Some(1.0), Some(9.0)),
                timeout_s: 10.0
            }
        );
        assert!(matches!(
            p[5],
            Step::Expect {
                test: Test::Changes,
                ..
            }
        ));
        for bad in [
            json!({"steps": [{"invoke": "k"}]}),
            json!({"steps": [{"deploy": "wy/s/dataflows", "def": {}}]}),
            json!({"steps": [{"oops": 1}]}),
            json!(3),
        ] {
            assert!(parse_plan(&bad).is_err(), "{bad}");
        }
    }
}
