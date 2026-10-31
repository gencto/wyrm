//! The engine against a tree in memory: lists answer from it, values come as samples, sinks
//! are recorded. Covers the DSA defects ADR 0025 names (`>=`, sublist removal) and the sink
//! rules (D5: nothing on start, only changes).

use std::collections::BTreeMap;

use wyrm_core::{NodeMeta, Quality, Sample, TypeCode, Value};
use wyrm_dql::{parse, Effect, Engine, Limits, Status};
use wyrm_link_api::ListChange;

/// A tree: key → meta; children are found by prefix.
struct Tree {
    nodes: BTreeMap<String, NodeMeta>,
    /// open lists: handle → key
    lists: BTreeMap<u64, String>,
    subs: BTreeMap<u64, String>,
    calls: Vec<Effect>,
    now: u64,
}

fn folder() -> NodeMeta {
    NodeMeta::default()
}

fn number() -> NodeMeta {
    NodeMeta {
        ty: Some(TypeCode::Number),
        ..NodeMeta::default()
    }
}

fn with_attr(mut m: NodeMeta, k: &str, v: &str) -> NodeMeta {
    m.attr
        .get_or_insert_with(BTreeMap::new)
        .insert(k.into(), Value::Str(v.into()));
    m
}

fn sample(v: Value) -> Sample {
    Sample {
        v,
        q: Quality::Good,
        t: 1,
    }
}

impl Tree {
    fn new(nodes: &[(&str, NodeMeta)]) -> Self {
        Self {
            nodes: nodes
                .iter()
                .map(|(k, m)| ((*k).to_owned(), m.clone()))
                .collect(),
            lists: BTreeMap::new(),
            subs: BTreeMap::new(),
            calls: Vec::new(),
            now: 1_000_000,
        }
    }

    fn children(&self, key: &str) -> Vec<(String, NodeMeta)> {
        let p = format!("{key}/");
        self.nodes
            .iter()
            .filter_map(|(k, m)| {
                let rest = k.strip_prefix(&p)?;
                (!rest.contains('/')).then(|| (rest.to_owned(), m.clone()))
            })
            .collect()
    }

    /// Applies effects; lists answer at once with their snapshot, which may open more lists.
    fn run(&mut self, e: &mut Engine, mut out: Vec<Effect>) {
        while !out.is_empty() {
            let mut next = Vec::new();
            for eff in out {
                match eff {
                    Effect::List { h, key, .. } => {
                        let snap = self.children(&key);
                        self.lists.insert(h, key);
                        e.on_list(h, ListChange::Refreshed(snap), self.now, &mut next);
                    }
                    Effect::Subscribe { h, key } => {
                        self.subs.insert(h, key);
                    }
                    Effect::Unsubscribe { h } => {
                        self.lists.remove(&h);
                        self.subs.remove(&h);
                    }
                    c @ (Effect::Invoke { .. } | Effect::Set { .. }) => self.calls.push(c),
                }
            }
            out = next;
        }
    }

    fn start(&mut self, text: &str) -> Engine {
        let mut e = Engine::new(parse(text).unwrap(), Limits::default());
        let mut out = Vec::new();
        e.start(self.now, &mut out);
        self.run(&mut e, out);
        e
    }

    /// A node appears or changes: its parent's list says so.
    fn put(&mut self, e: &mut Engine, key: &str, meta: NodeMeta) {
        let added = self.nodes.insert(key.to_owned(), meta.clone()).is_none();
        let (parent, name) = key.rsplit_once('/').unwrap();
        let hs: Vec<u64> = self
            .lists
            .iter()
            .filter(|(_, k)| *k == parent)
            .map(|(h, _)| *h)
            .collect();
        for h in hs {
            let c = if added {
                ListChange::Added(name.into(), meta.clone())
            } else {
                ListChange::Changed(name.into(), meta.clone())
            };
            let mut out = Vec::new();
            e.on_list(h, c, self.now, &mut out);
            self.run(e, out);
        }
    }

    fn remove(&mut self, e: &mut Engine, key: &str) {
        let p = format!("{key}/");
        self.nodes.retain(|k, _| k != key && !k.starts_with(&p));
        let (parent, name) = key.rsplit_once('/').unwrap();
        let hs: Vec<u64> = self
            .lists
            .iter()
            .filter(|(_, k)| *k == parent)
            .map(|(h, _)| *h)
            .collect();
        for h in hs {
            let mut out = Vec::new();
            e.on_list(h, ListChange::Removed(name.into()), self.now, &mut out);
            self.run(e, out);
        }
    }

    fn value(&mut self, e: &mut Engine, key: &str, v: Value) {
        let mut out = Vec::new();
        e.on_value(key, sample(v), self.now, &mut out);
        self.run(e, out);
    }
}

fn paths(e: &Engine) -> Vec<String> {
    e.table(0, 100)
        .into_iter()
        .map(|r| match r {
            Value::Map(m) => match m.get("path") {
                Some(Value::Str(s)) => s.clone(),
                _ => panic!("no path"),
            },
            _ => panic!("not a map"),
        })
        .collect()
}

fn col(e: &Engine, path: &str, c: &str) -> Value {
    e.table(0, 1000)
        .into_iter()
        .find_map(|r| match r {
            Value::Map(m) if m.get("path") == Some(&Value::Str(path.into())) => {
                Some(m.get(c).cloned().unwrap_or(Value::Null))
            }
            _ => None,
        })
        .expect("row")
}

fn plant() -> Tree {
    Tree::new(&[
        ("wy/s/downstream/plc", folder()),
        ("wy/s/downstream/plc/ahu1", folder()),
        (
            "wy/s/downstream/plc/ahu1/temp",
            with_attr(number(), "unit", "C"),
        ),
        (
            "wy/s/downstream/plc/ahu1/fan",
            NodeMeta {
                ty: Some(TypeCode::Bool),
                ..NodeMeta::default()
            },
        ),
        ("wy/s/downstream/plc/ahu2", folder()),
        (
            "wy/s/downstream/plc/ahu2/temp",
            with_attr(number(), "unit", "%"),
        ),
    ])
}

#[test]
fn lists_reach_as_deep_as_the_pattern_and_follow_changes() {
    let mut t = plant();
    let mut e = t.start("list wy/s/downstream/plc/** | where type == 'number'");
    assert_eq!(e.status(), Status::Ready);
    assert_eq!(
        paths(&e),
        [
            "wy/s/downstream/plc/ahu1/temp",
            "wy/s/downstream/plc/ahu2/temp"
        ]
    );
    // folders are listed, values are not (they have no children)
    assert_eq!(t.lists.len(), 3);
    assert!(t.subs.is_empty(), "no value column, no subscription");

    t.put(&mut e, "wy/s/downstream/plc/ahu3", folder());
    t.put(&mut e, "wy/s/downstream/plc/ahu3/temp", number());
    assert_eq!(paths(&e).len(), 3);
    // a node that stops matching leaves the table
    t.put(&mut e, "wy/s/downstream/plc/ahu3/temp", folder());
    assert_eq!(paths(&e).len(), 2);
    // a removed folder takes its rows and its lists with it
    t.remove(&mut e, "wy/s/downstream/plc/ahu1");
    assert_eq!(paths(&e), ["wy/s/downstream/plc/ahu2/temp"]);
    assert!(!t.lists.values().any(|k| k == "wy/s/downstream/plc/ahu1"));
}

#[test]
fn a_literal_pattern_lists_one_level() {
    let mut t = plant();
    let e = t.start("list wy/s/downstream/plc");
    assert_eq!(
        paths(&e),
        ["wy/s/downstream/plc/ahu1", "wy/s/downstream/plc/ahu2"]
    );
    assert_eq!(t.lists.len(), 1);
}

#[test]
fn values_columns_and_greater_or_equal() {
    let mut t = plant();
    let mut e = t.start(
        "list wy/s/downstream/plc/*/temp | subscribe value :name @unit | where value >= 20 \
         | expression f=\"value * 1.8 + 32.0\" bad=\"value / 0\"",
    );
    assert_eq!(
        t.subs.values().collect::<Vec<_>>(),
        ["wy/s/downstream/plc/**"]
    );
    // no value yet: `value >= 20` is not true (DSA's `>=` was an assignment: always true)
    assert!(paths(&e).is_empty());
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Float(19.0));
    assert!(paths(&e).is_empty());
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Float(20.0));
    assert_eq!(paths(&e), ["wy/s/downstream/plc/ahu1/temp"]);
    assert_eq!(
        col(&e, "wy/s/downstream/plc/ahu1/temp", "f"),
        Value::Float(68.0)
    );
    assert_eq!(
        col(&e, "wy/s/downstream/plc/ahu1/temp", ":name"),
        Value::Str("temp".into())
    );
    assert_eq!(
        col(&e, "wy/s/downstream/plc/ahu1/temp", "@unit"),
        Value::Str("C".into())
    );
    // an expression that fails gives null and counts, the row stays
    assert_eq!(col(&e, "wy/s/downstream/plc/ahu1/temp", "bad"), Value::Null);
    assert!(e.progress().errors > 0);
    assert!(t.lists.len() >= 2);
}

#[test]
fn a_value_cached_before_its_row_appears_is_used() {
    let mut t = plant();
    let mut e = t.start("list wy/s/downstream/plc/** | where type == 'number' | subscribe");
    t.value(&mut e, "wy/s/downstream/plc/ahu9/temp", Value::Int(5));
    t.put(&mut e, "wy/s/downstream/plc/ahu9", folder());
    t.put(&mut e, "wy/s/downstream/plc/ahu9/temp", number());
    assert_eq!(
        col(&e, "wy/s/downstream/plc/ahu9/temp", "value"),
        Value::Int(5)
    );
}

#[test]
fn dsa_filter_subscribes_its_columns() {
    let mut t = plant();
    let mut e = t.start("list wy/s/downstream/plc/** | filter $type=\"number\" @unit!=\"%\" value");
    assert_eq!(t.subs.len(), 1);
    assert!(paths(&e).is_empty(), "value does not exist yet");
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(1));
    t.value(&mut e, "wy/s/downstream/plc/ahu2/temp", Value::Int(1));
    assert_eq!(paths(&e), ["wy/s/downstream/plc/ahu1/temp"]);
}

#[test]
fn sublist_rows_go_with_their_parent() {
    let mut t = plant();
    // as DSA's list: a fixed pattern lists that node's children
    let mut e = t.start("list wy/s/downstream/plc | sublist ./*");
    assert_eq!(
        paths(&e),
        [
            "wy/s/downstream/plc/ahu1/fan",
            "wy/s/downstream/plc/ahu1/temp",
            "wy/s/downstream/plc/ahu2/temp"
        ]
    );
    // DSA removed the parent's path and left the child rows behind
    t.remove(&mut e, "wy/s/downstream/plc/ahu1");
    assert_eq!(paths(&e), ["wy/s/downstream/plc/ahu2/temp"]);
}

#[test]
fn sinks_fire_on_changes_only() {
    let mut t = plant();
    let mut e = t.start(
        "list wy/s/downstream/plc/*/temp | subscribe | set ../sp = value + 1 \
         | invoke wy/s/downstream/log/~act/note(p=%path, v=%value)",
    );
    // first complete values: the baseline, nothing goes out (D5)
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(20));
    assert!(t.calls.is_empty());
    // the same value again: nothing
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(20));
    assert!(t.calls.is_empty());
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(21));
    assert_eq!(t.calls.len(), 2);
    let (set_call, inv_call) = match (&t.calls[0], &t.calls[1]) {
        (
            Effect::Set { call, key, value },
            Effect::Invoke {
                call: c2,
                key: k2,
                action,
                args,
            },
        ) => {
            assert_eq!(key, "wy/s/downstream/plc/ahu1/sp");
            assert_eq!(*value, Value::Int(22));
            assert_eq!(k2, "wy/s/downstream/log");
            assert_eq!(action, "note");
            assert!(matches!(args, Value::Map(m) if m.get("v") == Some(&Value::Int(21))));
            (*call, *c2)
        }
        c => panic!("{c:?}"),
    };
    // while a call is in flight, changes wait; the newest goes when it answers
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(22));
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(23));
    assert_eq!(t.calls.len(), 2);
    let mut out = Vec::new();
    e.on_reply(set_call, true, t.now, &mut out);
    e.on_reply(inv_call, false, t.now, &mut out);
    t.run(&mut e, out);
    assert_eq!(t.calls.len(), 4);
    assert!(matches!(&t.calls[2], Effect::Set { value, .. } if *value == Value::Int(24)));
    assert_eq!(e.progress().errors, 1);
    assert_eq!(e.progress().sink_calls, 4);
}

#[test]
fn a_restart_with_the_same_values_calls_nothing() {
    // the engine of a restarted link sees the stored values again: they are the baseline
    let mut t = plant();
    let text = "list wy/s/downstream/plc/*/temp | subscribe | invoke ack(v=%value)";
    for _ in 0..2 {
        let mut e = t.start(text);
        t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(20));
        t.value(&mut e, "wy/s/downstream/plc/ahu2/temp", Value::Int(30));
    }
    assert!(t.calls.is_empty());
}

#[test]
fn throttle_holds_the_next_call() {
    let mut t = plant();
    let mut e = t.start(
        "list wy/s/downstream/plc/*/temp | subscribe | set ../sp = value | option throttle_ms=1000",
    );
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(1));
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(2));
    let call = match &t.calls[0] {
        Effect::Set { call, .. } => *call,
        c => panic!("{c:?}"),
    };
    let mut out = Vec::new();
    e.on_reply(call, true, t.now, &mut out);
    t.run(&mut e, out);
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(3));
    assert_eq!(t.calls.len(), 1, "held by the throttle");
    assert_eq!(e.next_wake_us(), Some(t.now + 1_000_000));
    t.now += 1_000_000;
    let mut out = Vec::new();
    e.tick(t.now, &mut out);
    t.run(&mut e, out);
    assert_eq!(t.calls.len(), 2);
}

#[test]
fn max_rows_keeps_the_first_and_refills() {
    let mut t = plant();
    let mut e = t.start("list wy/s/downstream/plc | option max_rows=1");
    assert_eq!(paths(&e), ["wy/s/downstream/plc/ahu1"]);
    assert!(e
        .progress()
        .error
        .as_deref()
        .unwrap()
        .starts_with("max_rows"));
    t.remove(&mut e, "wy/s/downstream/plc/ahu1");
    assert_eq!(paths(&e), ["wy/s/downstream/plc/ahu2"]);
}

#[test]
fn collecting_until_lists_answer_and_the_timeout() {
    let mut e = Engine::new(
        parse("list wy/s/downstream/plc/** | option timeout_s=5").unwrap(),
        Limits::default(),
    );
    let mut out = Vec::new();
    e.start(0, &mut out);
    let h = match &out[0] {
        Effect::List { h, key, full } => {
            assert_eq!(key, "wy/s/downstream/plc");
            assert!(!full);
            *h
        }
        o => panic!("{o:?}"),
    };
    assert_eq!(e.status(), Status::Collecting);
    assert_eq!(e.progress().lists_pending, 1);
    assert_eq!(e.next_wake_us(), Some(5_000_000));
    let mut out = Vec::new();
    e.tick(5_000_000, &mut out);
    assert_eq!(e.status(), Status::Ready);
    assert!(e
        .progress()
        .error
        .as_deref()
        .unwrap()
        .starts_with("incomplete"));
    // the list still counts when it answers later
    e.on_list(
        h,
        ListChange::Refreshed(vec![("a".into(), folder())]),
        6_000_000,
        &mut out,
    );
    assert_eq!(e.rows(), 1);
}

#[test]
fn a_link_that_goes_away_takes_its_rows() {
    let mut t = plant();
    let mut e = t.start("list wy/s/downstream/plc/**");
    assert!(e.rows() > 0);
    let h = *t
        .lists
        .iter()
        .find(|(_, k)| *k == "wy/s/downstream/plc")
        .unwrap()
        .0;
    let mut out = Vec::new();
    e.on_list(h, ListChange::Disconnected, t.now, &mut out);
    t.run(&mut e, out);
    assert_eq!(e.rows(), 0);
    assert_eq!(t.lists.len(), 1, "the top list stays for the reconnect");
}

#[test]
fn attributes_ask_for_full_meta() {
    let mut t = plant();
    let e = t.start("list wy/s/downstream/plc/** | where 'unit' in attr && attr.unit == '%'");
    assert_eq!(paths(&e), ["wy/s/downstream/plc/ahu2/temp"]);
    let mut e2 = Engine::new(
        parse("list wy/s/downstream | where 'unit' in attr").unwrap(),
        Limits::default(),
    );
    let mut out = Vec::new();
    e2.start(0, &mut out);
    assert!(matches!(&out[0], Effect::List { full: true, .. }));
}

#[test]
fn rows_without_values_refetch_their_subscription() {
    let mut t = plant();
    let mut e = t.start("list wy/s/downstream/plc/*/temp | subscribe");
    let first: Vec<u64> = t.subs.keys().copied().collect();
    assert_eq!(first.len(), 1);
    // ahu1's stored value came, ahu2's reply was lost
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(1));
    let at = e.next_wake_us().expect("a refetch is due");
    assert_eq!(at, t.now + 2_000_000);
    t.now = at;
    let mut out = Vec::new();
    e.tick(t.now, &mut out);
    t.run(&mut e, out);
    assert_eq!(e.progress().refetches, 1);
    assert_eq!(t.subs.len(), 1);
    assert_ne!(
        t.subs.keys().copied().collect::<Vec<_>>(),
        first,
        "a new subscription"
    );
    // the value comes on the new one: no more refetches
    t.value(&mut e, "wy/s/downstream/plc/ahu2/temp", Value::Int(2));
    assert_eq!(e.next_wake_us(), None);
    // a point that never has a value: three refetches at most (2, 4, 8 s)
    let mut t = plant();
    let mut e = t.start("list wy/s/downstream/plc/*/temp | subscribe");
    for _ in 0..5 {
        if let Some(at) = e.next_wake_us() {
            t.now = at;
            let mut out = Vec::new();
            e.tick(t.now, &mut out);
            t.run(&mut e, out);
        }
    }
    assert_eq!(e.progress().refetches, wyrm_dql::engine::MAX_REFETCHES);
    assert_eq!(e.next_wake_us(), None);
}

/// ADR 0025 item 4: a query reads and writes only what its author may.
#[test]
fn a_query_stays_within_its_authors_rights() {
    use wyrm_core::Perm;
    use wyrm_link_api::Who;
    let mut t = plant();
    let author = Who {
        authority: Some(vec![
            ("wy/s/downstream/**".into(), Perm::List),
            ("wy/s/downstream/plc/ahu1/**".into(), Perm::Write),
        ]),
        ..Who::default()
    };
    let text = "list wy/s/downstream/plc/** | where type == 'number' | subscribe | set ../../sp = value + 1";
    let mut e = Engine::new(parse(text).unwrap(), Limits::default()).with_rights(author, "s");
    let mut out = Vec::new();
    e.start(t.now, &mut out);
    t.run(&mut e, out);
    // ahu2 is listed (the link reads it) but is no row: its author may not read it
    assert_eq!(paths(&e), ["wy/s/downstream/plc/ahu1/temp"]);
    t.value(&mut e, "wy/s/downstream/plc/ahu2/temp", Value::Int(5));
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(20));
    assert_eq!(
        col(&e, "wy/s/downstream/plc/ahu1/temp", "value"),
        Value::Int(20)
    );
    // the sink climbs out of ahu1: refused when it would fire, counted as an error
    t.value(&mut e, "wy/s/downstream/plc/ahu1/temp", Value::Int(21));
    assert!(t.calls.is_empty(), "{:?}", t.calls);
    assert!(e.progress().errors >= 1);
    assert!(e
        .progress()
        .error
        .as_deref()
        .is_some_and(|m| m.contains("outside the rights")));
    // unknown rights: nothing at all
    let mut e =
        Engine::new(parse(text).unwrap(), Limits::default()).with_rights(Who::default(), "s");
    let mut out = Vec::new();
    e.start(t.now, &mut out);
    t.run(&mut e, out);
    assert!(paths(&e).is_empty());
    // a downstream site's keys: the own-site grants rewritten to it (as the gateway mints them)
    let mut t = Tree::new(&[
        ("wy/d/downstream/plc", folder()),
        ("wy/d/downstream/plc/t", number()),
        ("wy/d/downstream/other", folder()),
        ("wy/d/downstream/other/t", number()),
    ]);
    let author = Who {
        authority: Some(vec![("wy/s/downstream/plc/**".into(), Perm::Read)]),
        ..Who::default()
    };
    let mut e = Engine::new(parse("list wy/d/downstream/**").unwrap(), Limits::default())
        .with_rights(author, "s");
    let mut out = Vec::new();
    e.start(t.now, &mut out);
    t.run(&mut e, out);
    assert!(
        paths(&e)
            .iter()
            .all(|p| p.starts_with("wy/d/downstream/plc")),
        "{:?}",
        paths(&e)
    );
    assert!(paths(&e).contains(&"wy/d/downstream/plc/t".to_owned()));
}
