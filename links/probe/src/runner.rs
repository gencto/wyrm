//! Run a [`Scenario`] on one gateway connection and report every step.

use crate::scenario::{kind_of, render, same, text, texts, to_value, unset, within, Scenario};
use serde_json::Value as Json;
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use wyrm_core::Value;
use wyrm_gateway_client::{Conn, Event};

type Log = Arc<Mutex<Vec<(Instant, Event)>>>;

/// An open `list` or `subscribe` stream and what it delivered.
struct Feed {
    id: u64,
    log: Log,
    task: tokio::task::JoinHandle<()>,
}

/// One step's outcome.
#[derive(Debug, Clone)]
pub struct Row {
    pub step: usize,
    pub kind: String,
    pub target: String,
    /// `None`: skipped after an earlier failure.
    pub ok: Option<bool>,
    /// The callback's delay after the last action, or the step's time.
    pub ms: Option<u64>,
    pub detail: String,
}

#[derive(Debug, Clone)]
pub struct Report {
    pub name: String,
    pub rows: Vec<Row>,
    pub ms: u64,
}

impl Report {
    pub fn count(&self, ok: Option<bool>) -> usize {
        self.rows.iter().filter(|r| r.ok == ok).count()
    }

    pub fn passed(&self) -> bool {
        self.count(Some(false)) == 0
    }

    /// One record per step (the explorer shows it as a table).
    pub fn rows_value(&self) -> Value {
        Value::Array(
            self.rows
                .iter()
                .map(|r| {
                    let mut m = BTreeMap::from([
                        ("step".to_owned(), Value::UInt(r.step as u64)),
                        ("kind".to_owned(), Value::from(r.kind.as_str())),
                        ("target".to_owned(), Value::from(r.target.as_str())),
                        (
                            "result".to_owned(),
                            Value::from(match r.ok {
                                Some(true) => "ok",
                                Some(false) => "FAIL",
                                None => "skip",
                            }),
                        ),
                        ("detail".to_owned(), Value::from(r.detail.as_str())),
                    ]);
                    if let Some(ms) = r.ms {
                        m.insert("ms".into(), Value::UInt(ms));
                    }
                    Value::Map(m)
                })
                .collect(),
        )
    }

    /// Lines for a terminal.
    pub fn text(&self) -> String {
        let mut out = format!(
            "{}: {} ok, {} failed, {} skipped, {} ms\n",
            self.name,
            self.count(Some(true)),
            self.count(Some(false)),
            self.count(None),
            self.ms
        );
        for r in &self.rows {
            let mark = match r.ok {
                Some(true) => "ok  ",
                Some(false) => "FAIL",
                None => "skip",
            };
            let ms = r.ms.map(|m| format!(" {m} ms")).unwrap_or_default();
            out.push_str(&format!(
                "{:>3} {mark} {:<8} {}{ms}  {}\n",
                r.step, r.kind, r.target, r.detail
            ));
        }
        out
    }
}

/// `v` with the values of secret-looking fields (`token`, `password`,
/// `secret`, `key`) hidden: a report is shown to whoever runs the probe.
fn redact(v: &Value) -> Value {
    match v {
        Value::Map(m) => Value::Map(
            m.iter()
                .map(|(k, x)| {
                    let hide = ["token", "password", "secret", "key"]
                        .iter()
                        .any(|s| k.to_ascii_lowercase().contains(s));
                    (k.clone(), if hide { Value::from("***") } else { redact(x) })
                })
                .collect(),
        ),
        Value::Array(a) => Value::Array(a.iter().map(redact).collect()),
        other => other.clone(),
    }
}

fn short(v: &Value) -> String {
    let s = format!("{:?}", redact(v));
    if s.chars().count() > 120 {
        format!("{}…", s.chars().take(120).collect::<String>())
    } else {
        s
    }
}

/// What `save_as` keeps of a result: a text as it is, any other value in
/// short; with `field`, that text field of a map result (whole: `export`'s
/// `json` for a later `import`).
fn kept_text(v: &Value, field: Option<&str>) -> Result<String, String> {
    match (field, v) {
        (None, Value::Str(s)) => Ok(s.clone()),
        (None, other) => Ok(short(other)),
        (Some(f), Value::Map(m)) => match m.get(f) {
            Some(Value::Str(s)) => Ok(s.clone()),
            Some(_) => Err(format!("field {f} of the result is not a text")),
            None => Err(format!("no field {f} in the result")),
        },
        (Some(f), _) => Err(format!("field {f}: the result is not a map")),
    }
}

async fn open(conn: &Conn, op: &str, key: &str) -> Result<Feed, String> {
    let mut s = conn.stream(op, key).await.map_err(|e| e.to_string())?;
    let log: Log = Arc::new(Mutex::new(Vec::new()));
    let sink = log.clone();
    let id = s.id;
    let task = tokio::spawn(async move {
        while let Some(ev) = s.next().await {
            let closed = ev == Event::Closed;
            sink.lock()
                .unwrap_or_else(|p| p.into_inner())
                .push((Instant::now(), ev));
            if closed {
                return;
            }
        }
    });
    Ok(Feed { id, log, task })
}

/// Wait until `log` has an event after `since` that `hit` accepts; its
/// delay after `since`.
async fn expect(
    log: &Log,
    since: Instant,
    wait: Duration,
    hit: impl Fn(&Event) -> Option<String>,
) -> Result<(u64, String), String> {
    let deadline = Instant::now() + wait;
    loop {
        {
            let l = log.lock().unwrap_or_else(|p| p.into_inner());
            for (t, ev) in l.iter().filter(|(t, _)| *t >= since) {
                if let Some(d) = hit(ev) {
                    return Ok(((*t - since).as_millis() as u64, d));
                }
            }
            if l.iter().any(|(t, ev)| *t >= since && *ev == Event::Closed) {
                return Err("the stream closed".into());
            }
        }
        if Instant::now() >= deadline {
            let seen: Vec<String> = log
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .iter()
                .filter(|(t, _)| *t >= since)
                .map(|(_, ev)| match ev {
                    Event::Added(n, _) => format!("added {n}"),
                    Event::Changed(n, _) => format!("changed {n}"),
                    Event::Removed(n) => format!("removed {n}"),
                    Event::Sample { key, v, .. } => format!("{key} = {}", short(v)),
                    other => format!("{other:?}").chars().take(40).collect(),
                })
                .take(8)
                .collect();
            return Err(format!(
                "nothing in {} ms; since the action: [{}]",
                wait.as_millis(),
                seen.join(", ")
            ));
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

/// Run `sc`. `vars` start with `site` (and anything else the caller
/// gives); `run` is added if missing.
pub async fn run(conn: &Conn, sc: &Scenario, mut vars: BTreeMap<String, String>) -> Report {
    let started = Instant::now();
    vars.entry("run".into()).or_insert_with(|| {
        let n = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or_default();
        format!("{}", n % 100_000_000)
    });
    let mut watches: BTreeMap<String, Feed> = BTreeMap::new();
    let mut subs: Vec<Feed> = Vec::new();
    let mut mark = Instant::now();
    let mut failed = false;
    // a `require` found nothing: the rest does not apply
    let mut not_here = false;
    let saved: Vec<String> = sc
        .steps
        .iter()
        .filter_map(|s| text(s, "save_as").map(str::to_owned))
        .collect();
    let mut rows = Vec::new();
    for (i, raw) in sc.steps.iter().enumerate() {
        let cleanup = raw.get("cleanup") == Some(&Json::Bool(true));
        let step = render(raw, &vars);
        let kind = kind_of(&step).unwrap_or("?");
        let target = match kind {
            "sleep_ms" => step.get(kind).map(|v| v.to_string()).unwrap_or_default(),
            _ => text(&step, kind).unwrap_or_default().to_owned(),
        };
        let mut row = Row {
            step: i + 1,
            kind: kind.to_owned(),
            target: target.clone(),
            ok: None,
            ms: None,
            detail: String::new(),
        };
        if not_here {
            row.detail = "not on this site".into();
            rows.push(row);
            continue;
        }
        if failed && !cleanup {
            row.detail = "after a failure".into();
            rows.push(row);
            continue;
        }
        if let Some(var) = unset(&step, &saved) {
            row.detail = format!("{{{var}}} was not saved");
            rows.push(row);
            continue;
        }
        let t0 = Instant::now();
        let r: Result<(Option<u64>, String), String> = match kind {
            "require" => match conn.meta(&target).await {
                Ok(_) => Ok((None, "present".into())),
                Err(e) if e.is(wyrm_core::Status::NotFound) => {
                    not_here = true;
                    Ok((None, "absent: the scenario does not apply here".into()))
                }
                // No link owns the key (its liveliness is gone, spec 05): a
                // link this site does not run, or one that is down.
                Err(e) if e.is(wyrm_core::Status::Disconnected) => {
                    not_here = true;
                    Ok((
                        None,
                        "absent (its link is not connected): the scenario does not apply here"
                            .into(),
                    ))
                }
                Err(e) => Err(e.to_string()),
            },
            "watch" if watches.contains_key(&target) => Ok((None, "already watched".into())),
            "watch" => match open(conn, "list", &target).await {
                Ok(f) => {
                    let log = f.log.clone();
                    watches.insert(target.clone(), f);
                    expect(&log, t0, Duration::from_secs(5), |e| match e {
                        Event::Refreshed(k) => Some(format!("{} children", k.len())),
                        _ => None,
                    })
                    .await
                    .map(|(_, d)| (None, d))
                }
                Err(e) => Err(e),
            },
            "unwatch" => match watches.remove(&target) {
                Some(f) => {
                    f.task.abort();
                    conn.unsubscribe(f.id)
                        .await
                        .map(|_| (None, String::new()))
                        .map_err(|e| e.to_string())
                }
                None => Err("not watched".into()),
            },
            "sub" => match open(conn, "subscribe", &target).await {
                Ok(f) => {
                    subs.push(f);
                    Ok((None, String::new()))
                }
                Err(e) => Err(e),
            },
            "invoke" | "set" => {
                mark = Instant::now();
                let res = if kind == "invoke" {
                    let action = text(&step, "action").unwrap_or_default();
                    let args = step
                        .get("args")
                        .map(to_value)
                        .unwrap_or(Value::Map(BTreeMap::new()));
                    conn.invoke(&target, action, args).await
                } else {
                    let v = step.get("value").map(to_value).unwrap_or(Value::Null);
                    conn.set(&target, v).await.map(|_| None)
                };
                let want_error = text(&step, "expect") == Some("error");
                match (res, want_error) {
                    (Ok(v), false) => match (text(&step, "save_as"), &v) {
                        (Some(name), Some(v)) => kept_text(v, text(&step, "field")).map(|s| {
                            vars.insert(name.to_owned(), s);
                            (None, short(v))
                        }),
                        _ => Ok((None, v.as_ref().map(short).unwrap_or_default())),
                    },
                    (Ok(_), true) => Err("succeeded, an error was expected".into()),
                    (Err(e), true) => match text(&step, "error") {
                        Some(want) if !e.to_string().contains(want) => {
                            Err(format!("error {e}, expected one with {want:?}"))
                        }
                        _ => Ok((None, format!("refused as expected: {e}"))),
                    },
                    (Err(e), false) => Err(e.to_string()),
                }
            }
            "added" | "changed" | "removed" => match watches.get(&target) {
                None => Err(format!("{target} is not watched (add a watch step first)")),
                Some(f) => {
                    let want = text(&step, "name").unwrap_or("*").to_owned();
                    let matches = |n: &str| want == "*" || n == want;
                    let r = expect(&f.log, mark, within(&step), |e| match (kind, e) {
                        ("added", Event::Added(n, _))
                        | ("changed", Event::Changed(n, _))
                        | ("removed", Event::Removed(n))
                            if matches(n) =>
                        {
                            Some(n.clone())
                        }
                        _ => None,
                    })
                    .await;
                    if let (Ok((_, n)), Some(var)) = (&r, text(&step, "save_as")) {
                        vars.insert(var.to_owned(), n.clone());
                    }
                    r.map(|(ms, n)| (Some(ms), n))
                }
            },
            "value" => {
                let equals = step.get("equals").map(to_value);
                let mut out = Err(format!("{target} is not subscribed (add a sub step first)"));
                for f in &subs {
                    out = expect(&f.log, mark, within(&step), |e| match e {
                        Event::Sample { key, v, .. }
                            if *key == target && equals.as_ref().is_none_or(|w| same(w, v)) =>
                        {
                            Some(short(v))
                        }
                        _ => None,
                    })
                    .await
                    .map(|(ms, d)| (Some(ms), d));
                    if out.is_ok() {
                        break;
                    }
                }
                out
            }
            "meta" => match conn.meta(&target).await {
                Err(e) => Err(e.to_string()),
                Ok(m) => {
                    let actions: Vec<String> = m
                        .actions
                        .as_ref()
                        .map(|a| a.keys().cloned().collect())
                        .unwrap_or_default();
                    let kids = m.children.clone().unwrap_or_default();
                    let mut bad = Vec::new();
                    for a in texts(&step, "has_action") {
                        if !actions.contains(&a) {
                            bad.push(format!("no action {a}"));
                        }
                    }
                    for a in texts(&step, "lacks_action") {
                        if actions.contains(&a) {
                            bad.push(format!("action {a}"));
                        }
                    }
                    for c in texts(&step, "has_child") {
                        if !kids.contains(&c) {
                            bad.push(format!("no child {c}"));
                        }
                    }
                    for c in texts(&step, "lacks_child") {
                        if kids.contains(&c) {
                            bad.push(format!("child {c}"));
                        }
                    }
                    if let Some(t) = text(&step, "type") {
                        let has = m.ty.map(|t| t.name()).unwrap_or("none");
                        if has != t {
                            bad.push(format!("type {has}, not {t}"));
                        }
                    }
                    if bad.is_empty() {
                        Ok((
                            None,
                            format!("{} actions, {} children", actions.len(), kids.len()),
                        ))
                    } else {
                        Err(bad.join("; "))
                    }
                }
            },
            "children" => match conn.children(&target).await {
                Err(e) => Err(e.to_string()),
                Ok(kids) => {
                    let names: Vec<String> = kids.into_iter().map(|(n, _)| n).collect();
                    let missing: Vec<String> = texts(&step, "contains")
                        .into_iter()
                        .filter(|c| !names.contains(c))
                        .collect();
                    let extra: Vec<String> = texts(&step, "lacks")
                        .into_iter()
                        .filter(|c| names.contains(c))
                        .collect();
                    if missing.is_empty() && extra.is_empty() {
                        Ok((None, format!("{} children", names.len())))
                    } else {
                        Err(format!("missing {missing:?}, present {extra:?}"))
                    }
                }
            },
            "sleep_ms" => {
                let ms = step
                    .get("sleep_ms")
                    .and_then(Json::as_u64)
                    .unwrap_or(0)
                    .min(60_000);
                tokio::time::sleep(Duration::from_millis(ms)).await;
                Ok((None, String::new()))
            }
            _ => Err("unknown step".into()),
        };
        match r {
            Ok((ms, d)) => {
                row.ok = Some(true);
                row.ms = Some(ms.unwrap_or(t0.elapsed().as_millis() as u64));
                row.detail = d;
            }
            Err(e) => {
                row.ok = Some(false);
                row.ms = Some(t0.elapsed().as_millis() as u64);
                row.detail = e;
                failed = true;
            }
        }
        rows.push(row);
    }
    for (_, f) in watches
        .into_iter()
        .chain(subs.into_iter().map(|f| (String::new(), f)))
    {
        f.task.abort();
        let _ = conn.unsubscribe(f.id).await;
    }
    Report {
        name: sc.name.clone(),
        rows,
        ms: started.elapsed().as_millis() as u64,
    }
}

#[cfg(test)]
mod tests {
    use super::kept_text;
    use std::collections::BTreeMap;
    use wyrm_core::Value;

    #[test]
    fn save_as_keeps_a_text_or_a_field_of_a_map() {
        let long = "x".repeat(500);
        assert_eq!(kept_text(&Value::from("abc"), None), Ok("abc".into()));
        assert_eq!(kept_text(&Value::UInt(7), None), Ok("UInt(7)".into()));
        let m = Value::Map(BTreeMap::from([
            ("json".to_owned(), Value::Str(long.clone())),
            ("n".to_owned(), Value::UInt(1)),
        ]));
        assert_eq!(kept_text(&m, Some("json")), Ok(long), "whole, not cut");
        assert!(kept_text(&m, Some("n")).is_err());
        assert!(kept_text(&m, Some("other")).is_err());
        assert!(kept_text(&Value::from("abc"), Some("json")).is_err());
    }
}
