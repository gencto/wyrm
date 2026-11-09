//! The sources `subscribe` and `liveliness`, and the read field a port can change
//! (ADR 0040 §1, spec 06 0.2.22).
//!
//! A source reads the key of its config. A text on `in.key` replaces it: the old read ends
//! first, `out` goes `null` with quality `uncertain` until the new key's first sample, and the
//! new key is read only when the node's scope (`key_scope`) admits it ([`Scope::admit`]).
//! A refused value reads nothing and goes out as a text on `error`. Changes are at least
//! [`scope::RESUBSCRIBE`] apart; the latest value wins.

use crate::def::Map;
use crate::nodes::{Io, Msg, Node, Out, Tasks};
use crate::scope::{self, Scope};
use std::collections::BTreeMap;
use std::time::Duration;
use tokio::time::Instant;
use tracing::debug;
use wyrm_client::ValEvent;
use wyrm_core::{Quality, Value};
use wyrm_link_sdk::now_us;

/// What a sample on a read field's port asks for.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Switch {
    /// Read this key from now on.
    To { full: String, written: String },
    /// `null`: read nothing.
    Off,
    /// Not a key the scope admits: read nothing, and say why.
    Refused(String),
}

/// A read field that a port can change: its scope, the key in use, and the rate limit.
pub(crate) struct DynKey {
    scope_written: Option<String>,
    scope: Option<Result<Scope, String>>,
    /// The full key in use.
    current: Option<String>,
    refused: bool,
    waiting: Option<Value>,
    switched: Option<Instant>,
}

impl DynKey {
    pub(crate) fn new(cfg: &Map, scope_param: &str) -> Self {
        Self {
            scope_written: match cfg.get(scope_param) {
                Some(Value::Str(s)) => Some(s.clone()),
                _ => None,
            },
            scope: None,
            current: None,
            refused: false,
            waiting: None,
            switched: None,
        }
    }

    /// The key of the config is in use (it was approved as a static source).
    pub(crate) fn started(&mut self, full: String) {
        self.current = Some(full);
    }

    /// A sample on the field's port. `Some`: act on it now. `None`: it names the key in use,
    /// or it waits for [`DynKey::due`] (changes are [`scope::RESUBSCRIBE`] apart).
    pub(crate) fn offer(&mut self, v: Value, site: &str) -> Option<Switch> {
        let now = Instant::now();
        if self.switched.is_some_and(|t| now < t + scope::RESUBSCRIBE) {
            self.waiting = Some(v);
            return None;
        }
        self.decide(v, site, now)
    }

    /// The held value, once its time has come.
    pub(crate) fn due(&mut self, site: &str) -> Option<Switch> {
        let now = Instant::now();
        if self.switched.is_some_and(|t| now < t + scope::RESUBSCRIBE) {
            return None;
        }
        let v = self.waiting.take()?;
        self.decide(v, site, now)
    }

    /// A value waits for its time.
    pub(crate) fn waiting(&self) -> bool {
        self.waiting.is_some()
    }

    fn decide(&mut self, v: Value, site: &str, now: Instant) -> Option<Switch> {
        let sw = match &v {
            Value::Null => Switch::Off,
            v => {
                let scope = self.scope.get_or_insert_with(|| match &self.scope_written {
                    Some(w) => Scope::new(site, w),
                    None => Err("the node has no scope for a key from a port".into()),
                });
                match scope.as_ref().map_err(Clone::clone).and_then(|s| {
                    let full = s.admit(v)?;
                    Ok((full, v.clone()))
                }) {
                    Ok((full, Value::Str(written))) => Switch::To { full, written },
                    Ok(_) => Switch::Refused("the key is not a text".into()),
                    Err(why) => Switch::Refused(why),
                }
            }
        };
        // the key in use again changes nothing
        let same = match &sw {
            Switch::To { full, .. } => !self.refused && self.current.as_deref() == Some(full),
            Switch::Off => !self.refused && self.current.is_none() && self.switched.is_some(),
            Switch::Refused(_) => false,
        };
        if same {
            return None;
        }
        self.switched = Some(now);
        self.refused = matches!(sw, Switch::Refused(_));
        self.current = match &sw {
            Switch::To { full, .. } => Some(full.clone()),
            _ => None,
        };
        Some(sw)
    }
}

/// `subscribe` (values of a point) and `liveliness` (whether a node is alive).
pub(crate) struct Source {
    liveliness: bool,
    /// The key of the config, as written.
    start: Option<String>,
    key: DynKey,
    last: Option<Value>,
    /// The number of the read in use: samples of an earlier one are dropped.
    gen: u64,
    tasks: Tasks,
    io: Option<Io>,
    params: BTreeMap<String, Value>,
    rev: u64,
    error: Value,
}

impl Source {
    pub(crate) fn new(ty: &str, cfg: &Map) -> Self {
        Self {
            liveliness: ty == "liveliness",
            start: match cfg.get("key") {
                Some(Value::Str(k)) => Some(k.clone()),
                _ => None,
            },
            key: DynKey::new(cfg, "key_scope"),
            last: None,
            gen: 0,
            tasks: Tasks::default(),
            io: None,
            params: crate::catalog::effective_params(ty, cfg),
            rev: 0,
            error: Value::Null,
        }
    }

    /// Start reading `full`: the tasks end with the node or with the next key.
    fn open(&mut self, full: &str, io: &Io) {
        let gen = self.gen;
        let (src, lost) = (format!("__src.{gen}"), format!("__lost.{gen}"));
        if self.liveliness {
            let (io2, session, key) = (io.clone(), io.client.session().clone(), full.to_owned());
            self.tasks.0.push(tokio::spawn(async move {
                let Ok(sub) = session
                    .liveliness()
                    .declare_subscriber(&key)
                    .history(true)
                    .await
                else {
                    return;
                };
                while let Ok(s) = sub.recv_async().await {
                    let up = s.kind() == zenoh::sample::SampleKind::Put;
                    (io2.inject)(&src, Msg::new(Value::Bool(up), Quality::Good, now_us()));
                }
            }));
            return;
        }
        let (io2, client, pattern) = (io.clone(), io.client.clone(), full.to_owned());
        self.tasks.0.push(tokio::spawn(async move {
            let Ok(mut s) = client.subscribe(&pattern).await else {
                return;
            };
            while let Some(ev) = s.next().await {
                if let ValEvent::Sample { key, sample, .. } = ev {
                    (io2.inject)(
                        &src,
                        Msg {
                            v: sample.v,
                            q: sample.q,
                            t: sample.t,
                            key: Some(key.into()),
                        },
                    );
                }
            }
        }));
        // Owner gone → `bad/disconnected` with the previous value.
        if let Some(owner) = wyrm_client::owner_key(full).filter(|o| !o.contains('*')) {
            let (io3, session) = (io.clone(), io.client.session().clone());
            self.tasks.0.push(tokio::spawn(async move {
                let Ok(sub) = session.liveliness().declare_subscriber(&owner).await else {
                    return;
                };
                while let Ok(s) = sub.recv_async().await {
                    if s.kind() == zenoh::sample::SampleKind::Delete {
                        (io3.inject)(&lost, Msg::new(Value::Null, Quality::Bad, now_us()));
                    }
                }
            }));
        }
    }

    /// Another key from the port: the old read ends first, `out` is `null` and `uncertain`
    /// until the new key's first sample.
    fn switch(&mut self, sw: Switch, io: &Io, out: &mut Out) {
        self.tasks = Tasks::default();
        self.gen += 1;
        self.last = None;
        let now = now_us();
        out.emit("out", Msg::new(Value::Null, Quality::Uncertain, now));
        let (key, error) = match sw {
            Switch::To { full, written } => {
                self.open(&full, io);
                (Value::Str(written), Value::Null)
            }
            Switch::Off => (Value::Null, Value::Null),
            Switch::Refused(why) => {
                // the refused value is a value: it is not logged
                debug!("flow source: a key from its port was refused");
                (Value::Null, Value::Str(why))
            }
        };
        self.params.insert("key".into(), key);
        self.rev += 1;
        if error != self.error {
            self.error = error.clone();
            out.emit("error", Msg::new(error, Quality::Good, now));
        }
    }
}

impl Node for Source {
    fn start(&mut self, io: &Io) {
        self.io = Some(io.clone());
        if let Some(k) = self.start.clone() {
            let full = io.full_key(&k);
            self.open(&full, io);
            self.key.started(full);
        }
    }

    fn input(&mut self, port: &str, m: Msg, io: &Io, out: &mut Out) {
        if self.io.is_none() {
            self.io = Some(io.clone());
        }
        if port == "in.key" {
            if let Some(sw) = self.key.offer(m.v, &io.site) {
                self.switch(sw, io, out);
            }
            return;
        }
        let Some((kind, gen)) = port.strip_prefix("__").and_then(|p| p.split_once('.')) else {
            return;
        };
        if gen.parse::<u64>().ok() != Some(self.gen) {
            return; // a sample of a key that is no longer read
        }
        match kind {
            "src" => {
                self.last = Some(m.v.clone());
                out.emit("out", m);
            }
            "lost" => {
                if let Some(v) = self.last.clone() {
                    out.emit("out", Msg::new(v, Quality::Bad, m.t));
                }
            }
            _ => {}
        }
    }

    fn tick_every(&self) -> Option<Duration> {
        self.key.waiting().then_some(scope::RESUBSCRIBE)
    }

    fn tick(&mut self, _now: u64, out: &mut Out) {
        let Some(io) = self.io.clone() else { return };
        if let Some(sw) = self.key.due(&io.site) {
            self.switch(sw, &io, out);
        }
    }

    fn live_params(&self) -> Option<(u64, &BTreeMap<String, Value>)> {
        Some((self.rev, &self.params))
    }
}
