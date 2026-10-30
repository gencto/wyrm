//! The DQL engine alone, no host (ADR 0025 D4): `cargo bench -p wyrm-dql --bench engine`.
//!
//! A tree in memory, `folders` folders with `per` numbers each; lists answer at once.
//! Measured on the wall clock of this process, median of 5 rounds:
//! 1. **collect**: from `start` until the last list's snapshot is processed and every row is in
//!    the table (no values yet: columns stay null until samples come);
//! 2. **per sample**: the cost of one sample on a full table (the row is evaluated again).

use std::collections::BTreeMap;
use std::time::Instant;

use wyrm_core::{NodeMeta, Quality, Sample, TypeCode, Value};
use wyrm_dql::{parse, Effect, Engine, Limits};
use wyrm_link_api::ListChange;

fn tree(folders: usize, per: usize) -> BTreeMap<String, Vec<(String, NodeMeta)>> {
    let num = NodeMeta {
        ty: Some(TypeCode::Number),
        ..NodeMeta::default()
    };
    let mut t = BTreeMap::new();
    let root = "wy/s/downstream/m".to_owned();
    t.insert(
        root.clone(),
        (0..folders)
            .map(|i| (format!("f{i}"), NodeMeta::default()))
            .collect(),
    );
    for i in 0..folders {
        t.insert(
            format!("{root}/f{i}"),
            (0..per).map(|j| (format!("p{j}"), num.clone())).collect(),
        );
    }
    t
}

fn run(e: &mut Engine, t: &BTreeMap<String, Vec<(String, NodeMeta)>>, mut out: Vec<Effect>) {
    while !out.is_empty() {
        let mut next = Vec::new();
        for eff in out {
            if let Effect::List { h, key, .. } = eff {
                let snap = t.get(&key).cloned().unwrap_or_default();
                e.on_list(h, ListChange::Refreshed(snap), 0, &mut next);
            }
        }
        out = next;
    }
}

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(f64::total_cmp);
    v[v.len() / 2]
}

fn bench(label: &str, text: &str, folders: usize, per: usize) {
    let t = tree(folders, per);
    let rows = folders * per;
    let (mut collect, mut sample) = (Vec::new(), Vec::new());
    for _ in 0..5 {
        let mut e = Engine::new(parse(text).unwrap(), Limits::default());
        let t0 = Instant::now();
        let mut out = Vec::new();
        e.start(0, &mut out);
        run(&mut e, &t, out);
        collect.push(t0.elapsed().as_secs_f64() * 1000.0);
        assert_eq!(e.rows(), rows.min(5000), "{label}");
        let keys: Vec<String> = (0..folders)
            .flat_map(|i| (0..per).map(move |j| format!("wy/s/downstream/m/f{i}/p{j}")))
            .collect();
        let n = 200_000;
        let t0 = Instant::now();
        let mut out = Vec::new();
        for k in 0..n {
            let s = Sample {
                v: Value::Float(k as f64),
                q: Quality::Good,
                t: k as u64,
            };
            e.on_value(&keys[k % keys.len()], s, 0, &mut out);
            out.clear();
        }
        sample.push(t0.elapsed().as_secs_f64() * 1e9 / n as f64);
    }
    println!(
        "| {label} | {rows} | {:.2} | {:.0} | {:.0} |",
        median(collect),
        median(sample.clone()),
        1e9 / median(sample)
    );
}

fn main() {
    println!("| query | rows | collect ms | ns per sample | samples/s on one core |");
    println!("|---|---|---|---|---|");
    let all = "list wy/s/downstream/m/** | where type == 'number' | subscribe | option max_rows=5000";
    bench("where type + subscribe", all, 1000, 5);
    bench(
        "+ expression f = value * 1.8 + 32.0",
        &format!("{all} | expression f=\"value * 1.8 + 32.0\""),
        1000,
        5,
    );
    bench(
        "+ where value > 10.0 (after subscribe)",
        &format!("{all} | where value > 10.0"),
        1000,
        5,
    );
    bench("100 folders × 10", all, 100, 10);
}
