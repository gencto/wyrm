//! `wyr query "<DQL>"` (ADR 0025): the DQL engine over this client, with the user's own token.
//! The table is printed as it changes (at most every `--every-ms`), or once when it is complete
//! (`--once`). Nothing is stored. Sinks (`set`, `invoke`) are only printed unless `--sinks`.

use std::collections::HashMap;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use tokio::sync::mpsc;
use tokio::task::AbortHandle;
use wyrm_client::{ListEvent, ValEvent, WyrmClient};
use wyrm_core::{Sample, Value};
use wyrm_dql::{parse, Effect, Engine, Handle, Limits, Status};
use wyrm_link_api::ListChange;

use crate::{fmt_value, Error};

enum Msg {
    List(Handle, ListChange),
    Failed(Handle, String),
    Value(String, Sample),
    Reply(u64, bool),
}

fn now_us() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_micros() as u64)
        .unwrap_or(0)
}

fn change_of(ev: ListEvent) -> Option<ListChange> {
    Some(match ev {
        ListEvent::Refreshed(c) => {
            ListChange::Refreshed(c.into_iter().map(|c| (c.name, c.meta)).collect())
        }
        ListEvent::Added(c) => ListChange::Added(c.name, c.meta),
        ListEvent::Changed(c) => ListChange::Changed(c.name, c.meta),
        ListEvent::Removed(n) | ListEvent::Disconnected(Some(n)) => ListChange::Removed(n),
        ListEvent::Disconnected(None) => ListChange::Disconnected,
        ListEvent::Connected(_) => return None,
    })
}

struct Runner {
    c: WyrmClient,
    tx: mpsc::UnboundedSender<Msg>,
    tasks: HashMap<Handle, AbortHandle>,
    sinks: bool,
}

impl Runner {
    fn apply(&mut self, e: &mut Engine, effects: Vec<Effect>) {
        for eff in effects {
            match eff {
                Effect::List { h, key, full } => {
                    let (c, tx) = (self.c.clone(), self.tx.clone());
                    let t = tokio::spawn(async move {
                        let mut s = match c.list(&key).await {
                            Ok(s) => s,
                            Err(err) => {
                                let _ = tx.send(Msg::Failed(h, err.to_string()));
                                return;
                            }
                        };
                        while let Some(ev) = s.next().await {
                            let Some(mut ch) = change_of(ev) else {
                                continue;
                            };
                            if full {
                                ch = full_meta(&c, &key, ch).await;
                            }
                            if tx.send(Msg::List(h, ch)).is_err() {
                                return;
                            }
                        }
                    });
                    self.tasks.insert(h, t.abort_handle());
                }
                Effect::Subscribe { h, key } => {
                    let (c, tx) = (self.c.clone(), self.tx.clone());
                    let t = tokio::spawn(async move {
                        let mut s = match c.subscribe(&key).await {
                            Ok(s) => s,
                            Err(err) => {
                                let _ = tx.send(Msg::Failed(h, err.to_string()));
                                return;
                            }
                        };
                        while let Some(ev) = s.next().await {
                            if let ValEvent::Sample { key, sample, .. } = ev {
                                if tx.send(Msg::Value(key, sample)).is_err() {
                                    return;
                                }
                            }
                        }
                    });
                    self.tasks.insert(h, t.abort_handle());
                }
                Effect::Unsubscribe { h } => {
                    if let Some(t) = self.tasks.remove(&h) {
                        t.abort();
                    }
                }
                Effect::Set { call, key, value } => {
                    if !self.sinks {
                        eprintln!("would set {key} = {}", fmt_value(&value));
                        self.done(e, call, true);
                        continue;
                    }
                    let (c, tx) = (self.c.clone(), self.tx.clone());
                    tokio::spawn(async move {
                        let ok = c.set(&key, value).await.is_ok();
                        let _ = tx.send(Msg::Reply(call, ok));
                    });
                }
                Effect::Invoke {
                    call,
                    key,
                    action,
                    args,
                } => {
                    if !self.sinks {
                        eprintln!("would invoke {key}/~act/{action}({})", fmt_value(&args));
                        self.done(e, call, true);
                        continue;
                    }
                    let (c, tx) = (self.c.clone(), self.tx.clone());
                    tokio::spawn(async move {
                        let ok = c.invoke_one(&key, &action, args).await.is_ok();
                        let _ = tx.send(Msg::Reply(call, ok));
                    });
                }
            }
        }
    }

    fn done(&mut self, e: &mut Engine, call: u64, ok: bool) {
        let mut out = Vec::new();
        e.on_reply(call, ok, now_us(), &mut out);
        self.apply(e, out);
    }
}

/// Children with their whole `~meta` (the query reads `attr`, `actions` or `meta`).
async fn full_meta(c: &WyrmClient, key: &str, ch: ListChange) -> ListChange {
    let meta = |name: String, summary| async move {
        c.meta(&format!("{key}/{name}")).await.unwrap_or(summary)
    };
    match ch {
        ListChange::Refreshed(kids) => {
            let mut out = Vec::with_capacity(kids.len());
            for (n, m) in kids {
                out.push((n.clone(), meta(n, m).await));
            }
            ListChange::Refreshed(out)
        }
        ListChange::Added(n, m) => ListChange::Added(n.clone(), meta(n, m).await),
        ListChange::Changed(n, m) => ListChange::Changed(n.clone(), meta(n, m).await),
        other => other,
    }
}

fn to_json(v: &Value) -> serde_json::Value {
    use serde_json::Value as J;
    match v {
        Value::Null => J::Null,
        Value::Bool(b) => J::Bool(*b),
        Value::Int(i) => J::from(*i),
        Value::UInt(u) => J::from(*u),
        Value::Float(f) => serde_json::Number::from_f64(*f).map_or(J::Null, J::Number),
        Value::Str(s) => J::String(s.clone()),
        Value::Bytes(b) => J::String(hex::encode(b)),
        Value::Array(a) => J::Array(a.iter().map(to_json).collect()),
        Value::Map(m) => J::Object(m.iter().map(|(k, v)| (k.clone(), to_json(v))).collect()),
    }
}

fn print(e: &Engine, json: bool) {
    let rows = e.table(0, wyrm_dql::engine::MAX_ROWS);
    if json {
        let j = serde_json::json!({
            "status": e.status().name(),
            "rows": rows.iter().map(to_json).collect::<Vec<_>>(),
            "error": e.progress().error,
        });
        out!("{j}");
        return;
    }
    let cols = e.columns();
    out!("-- {} rows, {} --", rows.len(), e.status().name());
    out!("{}", cols.join("\t"));
    for r in &rows {
        let Value::Map(m) = r else { continue };
        let line: Vec<String> = cols
            .iter()
            .map(|c| m.get(c).map(fmt_value).unwrap_or_default())
            .collect();
        out!("{}", line.join("\t"));
    }
    if let Some(err) = &e.progress().error {
        out!("-- {err}");
    }
}

pub async fn run(
    c: &WyrmClient,
    text: &str,
    once: bool,
    every_ms: u64,
    json: bool,
    sinks: bool,
) -> Result<(), Error> {
    let plan = parse(text).map_err(|e| e.to_string())?;
    let mut e = Engine::new(plan, Limits::default());
    let (tx, mut rx) = mpsc::unbounded_channel();
    let mut r = Runner {
        c: c.clone(),
        tx,
        tasks: HashMap::new(),
        sinks,
    };
    let mut out = Vec::new();
    e.start(now_us(), &mut out);
    r.apply(&mut e, out);
    let mut tick = tokio::time::interval(Duration::from_millis(every_ms.max(50)));
    loop {
        tokio::select! {
            Some(m) = rx.recv() => {
                let now = now_us();
                let mut out = Vec::new();
                match m {
                    Msg::List(h, ch) => e.on_list(h, ch, now, &mut out),
                    Msg::Failed(h, err) => e.failed(h, &err, now),
                    Msg::Value(k, s) => e.on_value(&k, s, now, &mut out),
                    Msg::Reply(call, ok) => e.on_reply(call, ok, now, &mut out),
                }
                r.apply(&mut e, out);
            }
            _ = tick.tick() => {
                let mut out = Vec::new();
                e.tick(now_us(), &mut out);
                r.apply(&mut e, out);
                if once {
                    if e.status() == Status::Ready {
                        print(&e, json);
                        break;
                    }
                } else if e.take_dirty() {
                    print(&e, json);
                }
            }
        }
    }
    for (_, t) in r.tasks.drain() {
        t.abort();
    }
    Ok(())
}
