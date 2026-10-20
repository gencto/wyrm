//! `wyr record` / `wyr replay`: run a flow definition offline on recorded
//! samples.
//!
//! Recording format (`.cbor`): one CBOR array (definite or indefinite
//! length) of maps `{"key": tstr, "sample": Sample}`, where `key` is the
//! full node key without `/~val` (`wy/local/down/mock/g0/p0`) and `Sample`
//! is the spec 03 `~val` payload `{0: v, 1: q, 2: t}` (t in µs since the
//! Unix epoch). Unknown map keys are skipped.
//!
//! Replay starts the flow engine in-process on an isolated Zenoh session
//! (no network, temporary state directory), deploys the definition with
//! an ephemeral admin key, then publishes the samples in `t` order on
//! their `~val` keys, paced by the recorded time differences divided by
//! `--speed`, pauses capped at `--max-gap-s`. Timestamps are moved to the replay clock, so time-based
//! nodes (`window`, `alarm` delays, `delay`, `timer`, `age_ms`) see the
//! replay time: at `--speed` ≠ 1 they see compressed or stretched time.
//! It prints every `~val` the flow publishes (`flows/<id>/nodes/**`) and
//! every command of `set`/`invoke` sinks; commands are acknowledged with
//! `ok` and never reach a device.

use crate::flow::{deploy_args, parse_def, root};
use crate::{fmt_value, Error};
use minicbor::data::Type;
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use wyrm_client::{SigningTokens, ValEvent, WyrmClient};
use wyrm_core::{Attachment, Quality, Sample, SetRequest, Status, Value};
use wyrm_flow::{Engine, EngineStart, FlowHost};
use wyrm_link_sdk::{now_us, LinkConfig};

#[derive(Debug, Clone, PartialEq)]
pub struct Record {
    pub key: String,
    pub sample: Sample,
}

pub fn encode(records: &[Record]) -> Result<Vec<u8>, Error> {
    let mut e = minicbor::Encoder::new(Vec::new());
    e.array(records.len() as u64)?;
    for r in records {
        e.map(2)?
            .str("key")?
            .str(&r.key)?
            .str("sample")?
            .encode(&r.sample)?;
    }
    Ok(e.into_writer())
}

pub fn decode(bytes: &[u8]) -> Result<Vec<Record>, Error> {
    let mut d = minicbor::Decoder::new(bytes);
    let len = d.array()?;
    let mut out = Vec::new();
    loop {
        match len {
            Some(n) if out.len() as u64 == n => break,
            None if d.datatype()? == Type::Break => break,
            _ => {}
        }
        let i = out.len();
        let n = d
            .map()?
            .ok_or_else(|| format!("record {i}: indefinite map"))?;
        let (mut key, mut sample) = (None, None);
        for _ in 0..n {
            match d.str()? {
                "key" => key = Some(d.str()?.to_owned()),
                "sample" => sample = Some(d.decode::<Sample>()?),
                _ => d.skip()?,
            }
        }
        match (key, sample) {
            (Some(key), Some(sample)) => out.push(Record { key, sample }),
            _ => return Err(format!("record {i}: needs key and sample").into()),
        }
    }
    Ok(out)
}

/// `wyr record`: subscribe to `pattern` for `secs` seconds (or until
/// Ctrl-C) and write the samples. Stored last values come first.
pub async fn record(
    c: &WyrmClient,
    pattern: &str,
    out: &Path,
    secs: Option<u64>,
) -> Result<(), Error> {
    if out.exists() {
        return Err(format!("{} exists; not overwriting", out.display()).into());
    }
    let mut s = c.subscribe(pattern).await?;
    let mut records = Vec::new();
    let until = async {
        match secs {
            Some(n) => tokio::time::sleep(Duration::from_secs(n)).await,
            None => std::future::pending().await,
        }
    };
    tokio::pin!(until);
    eprintln!(
        "recording {pattern} into {} ({}; Ctrl-C to stop)",
        out.display(),
        secs.map(|n| format!("{n} s"))
            .unwrap_or_else(|| "no time limit".into())
    );
    loop {
        tokio::select! {
            _ = &mut until => break,
            _ = tokio::signal::ctrl_c() => break,
            ev = s.next() => match ev {
                Some(ValEvent::Sample { key, sample, .. }) => records.push(Record { key, sample }),
                Some(ValEvent::Removed(_)) => {}
                None => break,
            },
        }
    }
    std::fs::write(out, encode(&records)?).map_err(|e| format!("{}: {e}", out.display()))?;
    out!("{} samples written to {}", records.len(), out.display());
    Ok(())
}

/// What a replay printed: flow outputs and sink commands, one line each.
#[derive(Debug, Default, Clone)]
pub struct Summary {
    pub inputs: usize,
    pub outputs: Vec<String>,
    pub commands: Vec<String>,
}

type Lines = Arc<std::sync::Mutex<Vec<String>>>;

fn emit(lines: &Lines, line: String) {
    out!("{line}");
    lines.lock().unwrap_or_else(|p| p.into_inner()).push(line);
}

fn take(lines: &Lines) -> Vec<String> {
    std::mem::take(&mut *lines.lock().unwrap_or_else(|p| p.into_inner()))
}

pub struct ReplayArgs {
    pub file: PathBuf,
    pub flow: PathBuf,
    pub site: Option<String>,
    pub speed: f64,
    /// Longer pauses between recorded samples are shortened to this
    /// (stored last values may be hours older than the live ones).
    pub max_gap: Option<Duration>,
    pub settle: Duration,
}

/// Replay offset of each record in µs at `speed` 1: recorded time
/// differences, each capped at `max_gap`.
fn schedule(records: &[Record], max_gap: Option<Duration>) -> Vec<u64> {
    let cap = max_gap.map_or(u64::MAX, |g| g.as_micros().try_into().unwrap_or(u64::MAX));
    let mut at = 0u64;
    let mut prev = records.first().map(|r| r.sample.t).unwrap_or(0);
    records
        .iter()
        .map(|r| {
            at += r.sample.t.saturating_sub(prev).min(cap);
            prev = r.sample.t;
            at
        })
        .collect()
}

/// Zenoh config for an isolated in-process session (no listeners, no
/// scouting): nothing leaves the process.
fn isolated_config() -> Result<zenoh::Config, Error> {
    let mut c = zenoh::Config::default();
    for (k, v) in [
        ("mode", r#""peer""#),
        ("listen/endpoints", "[]"),
        ("connect/endpoints", "[]"),
        ("scouting/multicast/enabled", "false"),
        ("scouting/gossip/enabled", "false"),
    ] {
        c.insert_json5(k, v)?;
    }
    Ok(c)
}

fn site_of(key: &str) -> Option<&str> {
    key.strip_prefix("wy/")?.split('/').next()
}

fn full_key(site: &str, k: &str) -> String {
    if k.starts_with("wy/") {
        k.to_owned()
    } else {
        format!("wy/{site}/{}", k.trim_start_matches('/'))
    }
}

/// Seconds of recorded time since the replay start.
fn offset(t: u64, start: u64, speed: f64) -> String {
    format!("+{:.3}s", t.saturating_sub(start) as f64 * speed / 1e6)
}

fn quality(q: Quality, qual: Option<String>) -> String {
    match (q, qual) {
        (_, Some(s)) => format!(" {s}"),
        (Quality::Good, None) => String::new(),
        (q, None) => format!(" {}", q.name()),
    }
}

pub async fn replay(a: ReplayArgs) -> Result<Summary, Error> {
    if !(a.speed > 0.0 && a.speed <= 10_000.0) {
        return Err("--speed must be in (0, 10000]".into());
    }
    let bytes = std::fs::read(&a.file).map_err(|e| format!("{}: {e}", a.file.display()))?;
    let mut records = decode(&bytes).map_err(|e| format!("{}: {e}", a.file.display()))?;
    records.sort_by_key(|r| r.sample.t);
    let text =
        std::fs::read_to_string(&a.flow).map_err(|e| format!("{}: {e}", a.flow.display()))?;
    let raw = parse_def(&text).map_err(|e| format!("{}: {e}", a.flow.display()))?;
    let (def, _) = wyrm_flow::def::compile(&raw).map_err(|e| format!("flow definition: {e}"))?;
    let site = match &a.site {
        Some(s) => s.clone(),
        None => records
            .iter()
            .find_map(|r| site_of(&r.key))
            .unwrap_or("local")
            .to_owned(),
    };
    wyrm_core::keyspace::validate_segment(&site).map_err(|e| format!("site: {e}"))?;
    let id = def.id.clone();

    let dir = std::env::temp_dir().join(format!("wyr-replay-{}-{}", std::process::id(), now_us()));
    let result = run_replay(&a, records, raw, &def, &site, &dir).await;
    let _ = std::fs::remove_dir_all(&dir);
    result.map_err(|e| format!("replay of {id}: {e}").into())
}

async fn run_replay(
    a: &ReplayArgs,
    records: Vec<Record>,
    raw: Value,
    def: &wyrm_flow::def::FlowDef,
    site: &str,
    dir: &Path,
) -> Result<Summary, Error> {
    let session = zenoh::open(isolated_config()?).await?;
    let mut seed = [0u8; 32];
    getrandom::fill(&mut seed).map_err(|e| format!("no randomness: {e}"))?;
    let key = ed25519_dalek::SigningKey::from_bytes(&seed);
    let host = FlowHost::open(dir, &seed, site)?;
    let mut lcfg = LinkConfig::new(site, "flows");
    lcfg.root = Some(root(site));
    lcfg.admin_keys = vec![key.verifying_key()];
    let engine = wyrm_link_sdk::spawn::<Engine>(
        session.clone(),
        lcfg,
        EngineStart {
            host,
            admin_keys: vec![key.verifying_key()],
        },
    )
    .await?;

    let start = now_us();
    let speed = a.speed;
    let outputs = Lines::default();
    let commands = Lines::default();
    // Flow outputs and flow state.
    let flow_node = format!("{}/{}", root(site), def.id);
    let c = WyrmClient::new(session.clone())
        .with_tokens(Arc::new(SigningTokens::new(key, site)))
        .with_timeout(Duration::from_secs(5));
    let mut outs = c.subscribe(&format!("{flow_node}/nodes/**")).await?;
    let prefix = format!("{flow_node}/nodes/");
    let n_out = outputs.clone();
    let printer = tokio::spawn(async move {
        while let Some(ev) = outs.next().await {
            if let ValEvent::Sample { key, sample, qual } = ev {
                let line = format!(
                    "{} {} = {}{}",
                    offset(sample.t, start, speed),
                    key.strip_prefix(&prefix).unwrap_or(&key),
                    fmt_value(&sample.v),
                    quality(sample.q, qual)
                );
                emit(&n_out, line);
            }
        }
    });
    let mut state = c.subscribe(&flow_node).await?;
    let state_printer = tokio::spawn(async move {
        while let Some(ev) = state.next().await {
            if let ValEvent::Sample { sample, .. } = ev {
                if let Value::Map(m) = &sample.v {
                    if let Some(Value::Str(e)) = m.get("error") {
                        out!("{} flow error: {e}", offset(sample.t, start, speed));
                    }
                }
            }
        }
    });
    let sinks = sinks(&session, site, start, speed, commands.clone()).await?;

    // Deploy.
    let args = deploy_args(raw, site, &|k| c.proof(k))?;
    c.invoke_one(&root(site), "deploy", args).await?;

    // Publishers; wait until the flow's subscribers match.
    let patterns: Vec<zenoh::key_expr::OwnedKeyExpr> = def
        .nodes
        .values()
        .filter(|n| n.ty == "subscribe")
        .filter_map(|n| match n.cfg.get("key") {
            Some(Value::Str(k)) => {
                zenoh::key_expr::OwnedKeyExpr::autocanonize(format!("{}/~val", full_key(site, k)))
                    .ok()
            }
            _ => None,
        })
        .collect();
    let keys: BTreeSet<&str> = records.iter().map(|r| r.key.as_str()).collect();
    let mut pubs = BTreeMap::new();
    let mut unused = Vec::new();
    for k in &keys {
        let ke = zenoh::key_expr::OwnedKeyExpr::autocanonize(format!("{k}/~val"))
            .map_err(|e| format!("record key {k}: {e}"))?;
        if !patterns.iter().any(|p| p.intersects(&ke)) {
            unused.push(*k);
        }
        pubs.insert(*k, session.declare_publisher(ke).await?);
    }
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    for (k, p) in &pubs {
        if unused.contains(k) {
            continue;
        }
        while !p.matching_status().await?.matching() {
            if tokio::time::Instant::now() > deadline {
                return Err(format!("the flow did not subscribe to {k} within 5 s").into());
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    }
    if !unused.is_empty() {
        eprintln!(
            "note: no subscribe node reads {} recorded key(s), e.g. {}",
            unused.len(),
            unused[0]
        );
    }
    eprintln!(
        "replaying {} samples of {} keys into flow {} (site {site}, speed {speed})",
        records.len(),
        keys.len(),
        def.id
    );

    // Feed, paced on the replay clock.
    let feed_start = now_us();
    for (r, at) in records.iter().zip(schedule(&records, a.max_gap)) {
        let due = feed_start + (at as f64 / speed) as u64;
        let now = now_us();
        if due > now {
            tokio::time::sleep(Duration::from_micros(due - now)).await;
        }
        let s = Sample {
            v: r.sample.v.clone(),
            q: r.sample.q,
            t: due.max(now),
        };
        pubs[r.key.as_str()]
            .put(wyrm_core::codec::to_vec(&s)?)
            .await?;
    }
    tokio::time::sleep(a.settle).await;
    engine.stop().await;
    printer.abort();
    state_printer.abort();
    sinks.abort();
    let summary = Summary {
        inputs: records.len(),
        outputs: take(&outputs),
        commands: take(&commands),
    };
    eprintln!(
        "done: {} samples in, {} outputs, {} commands",
        summary.inputs,
        summary.outputs.len(),
        summary.commands.len()
    );
    let _ = session.close().await;
    Ok(summary)
}

/// Stand-ins for the devices behind `set`/`invoke` sinks: print the
/// command and answer `ok`.
async fn sinks(
    session: &zenoh::Session,
    site: &str,
    start: u64,
    speed: f64,
    lines: Lines,
) -> Result<tokio::task::JoinHandle<()>, Error> {
    let set = session
        .declare_queryable(format!("wy/{site}/down/**/~set"))
        .await?;
    let act = session
        .declare_queryable(format!("wy/{site}/down/**/~act/*"))
        .await?;
    let ok = wyrm_core::codec::to_vec(&Attachment::with_status(Status::Ok))?;
    Ok(tokio::spawn(async move {
        loop {
            let q = tokio::select! {
                q = set.recv_async() => q,
                q = act.recv_async() => q,
            };
            let Ok(q) = q else { return };
            let key = q.key_expr().as_str().to_owned();
            let payload = q
                .payload()
                .map(|p| p.to_bytes().to_vec())
                .unwrap_or_default();
            let when = offset(now_us(), start, speed);
            if let Some(node) = key.strip_suffix("/~set") {
                let v = wyrm_core::codec::from_slice::<SetRequest>(&payload)
                    .map(|r| fmt_value(&r.v))
                    .unwrap_or_else(|_| "?".into());
                emit(
                    &lines,
                    format!("{when} set {node} = {v}  (offline: not sent)"),
                );
            } else {
                let args = wyrm_core::codec::from_slice::<Value>(&payload)
                    .map(|v| fmt_value(&v))
                    .unwrap_or_default();
                emit(
                    &lines,
                    format!("{when} invoke {key} {args}  (offline: not sent)"),
                );
            }
            let _ = q
                .reply(q.key_expr().clone(), Vec::<u8>::new())
                .attachment(ok.clone())
                .await;
        }
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rec(key: &str, v: Value, t: u64) -> Record {
        Record {
            key: key.into(),
            sample: Sample {
                v,
                q: Quality::Good,
                t,
            },
        }
    }

    #[test]
    fn recording_round_trip() {
        let rs = vec![
            rec("wy/s/down/m/p0", Value::Float(21.5), 1_000_000),
            rec("wy/s/down/m/p1", Value::from("x"), 1_000_100),
            Record {
                key: "wy/s/down/m/p0".into(),
                sample: Sample {
                    v: Value::Null,
                    q: Quality::Bad,
                    t: 2_000_000,
                },
            },
        ];
        let bytes = encode(&rs).unwrap();
        assert_eq!(decode(&bytes).unwrap(), rs);
        assert_eq!(decode(&encode(&[]).unwrap()).unwrap(), vec![]);
        // indefinite array, unknown keys skipped
        let mut e = minicbor::Encoder::new(Vec::new());
        e.begin_array().unwrap();
        e.map(3).unwrap();
        e.str("note").unwrap().u8(1).unwrap();
        e.str("key").unwrap().str("wy/s/down/m/p0").unwrap();
        e.str("sample").unwrap().encode(&rs[0].sample).unwrap();
        e.end().unwrap();
        assert_eq!(decode(&e.into_writer()).unwrap(), vec![rs[0].clone()]);
        // missing sample
        let mut e = minicbor::Encoder::new(Vec::new());
        e.array(1).unwrap().map(1).unwrap();
        e.str("key").unwrap().str("k").unwrap();
        assert!(decode(&e.into_writer()).is_err());
        assert!(decode(b"\x01").is_err());
    }

    #[test]
    fn keys_and_sites() {
        assert_eq!(site_of("wy/plant/down/m/p0"), Some("plant"));
        assert_eq!(site_of("x/y"), None);
        assert_eq!(full_key("s", "down/m/p0"), "wy/s/down/m/p0");
        assert_eq!(full_key("s", "/down/m/p0"), "wy/s/down/m/p0");
        assert_eq!(full_key("s", "wy/t/down/x"), "wy/t/down/x");
        assert_eq!(offset(3_500_000, 1_000_000, 2.0), "+5.000s");
    }

    #[test]
    fn gaps_are_capped() {
        let rs = [
            rec("k", Value::Null, 1_000),
            rec("k", Value::Null, 3_600_000_000),
            rec("k", Value::Null, 3_600_500_000),
        ];
        assert_eq!(schedule(&rs, None), [0, 3_599_999_000, 3_600_499_000]);
        assert_eq!(
            schedule(&rs, Some(Duration::from_secs(2))),
            [0, 2_000_000, 2_500_000]
        );
        assert!(schedule(&[], None).is_empty());
    }

    /// End to end: recorded samples → flow (expression + alarm + set
    /// sink) → printed outputs; checked through the counters.
    #[tokio::test(flavor = "multi_thread")]
    async fn replays_a_flow() {
        let dir = std::env::temp_dir().join(format!("wyr-replay-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let t0 = 1_700_000_000_000_000u64;
        let rs: Vec<Record> = (0..10)
            .map(|i| {
                rec(
                    "wy/s/down/m/p0",
                    Value::Float(f64::from(i) * 5.0),
                    t0 + i as u64 * 20_000,
                )
            })
            .collect();
        let file = dir.join("in.cbor");
        std::fs::write(&file, encode(&rs).unwrap()).unwrap();
        let flow = dir.join("f.json5");
        std::fs::write(
            &flow,
            r#"{
                id: "f", version: 1,
                nodes: {
                    a: { type: "subscribe", key: "down/m/p0" },
                    x: { type: "expression", inputs: ["a"], expr: "a.v * 2.0" },
                    al: { type: "alarm", high: 60 },
                    o: { type: "publish", node: "o" },
                    cmd: { type: "set", path: "down/m/sp" },
                },
                edges: [["a.out", "x.in.a"], ["x.out", "o.in"], ["x.out", "al.in"], ["al.out", "cmd.in"]],
                permissions: { maxperm: "write" },
            }"#,
        )
        .unwrap();
        let s = replay(ReplayArgs {
            file,
            flow,
            site: None,
            speed: 1.0,
            max_gap: Some(Duration::from_secs(5)),
            // generous: the workspace suite loads the machine
            settle: Duration::from_millis(1500),
        })
        .await
        .unwrap();
        assert_eq!(s.inputs, 10);
        assert!(s.outputs.iter().any(|l| l.ends_with(" o = 90")), "{s:?}");
        assert!(s.outputs.iter().all(|l| l.starts_with('+')), "{s:?}");
        assert_eq!(
            s.commands
                .iter()
                .filter(|l| l.contains("set wy/s/down/m/sp = true"))
                .count(),
            1,
            "{s:?}"
        );
        // bad inputs
        let e = replay(ReplayArgs {
            file: dir.join("missing.cbor"),
            flow: dir.join("f.json5"),
            site: None,
            speed: 1.0,
            max_gap: None,
            settle: Duration::ZERO,
        })
        .await;
        assert!(e.is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
