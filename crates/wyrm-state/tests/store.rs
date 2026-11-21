#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use minicbor::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;
use wyrm_state::{State, StateError, Store};

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
struct Kv {
    map: BTreeMap<String, u32>,
}

#[derive(Debug, Encode, Decode)]
enum Op {
    #[n(0)]
    Put(#[n(0)] String, #[n(1)] u32),
    #[n(1)]
    Del(#[n(0)] String),
}

impl State for Kv {
    const SCHEMA: u32 = 1;
    type Op = Op;
    fn apply(&mut self, op: &Op) -> Result<(), String> {
        match op {
            Op::Put(k, v) => {
                self.map.insert(k.clone(), *v);
            }
            Op::Del(k) => {
                self.map.remove(k).ok_or_else(|| format!("no key {k}"))?;
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct KvV2 {
    map: BTreeMap<String, u32>,
}
impl State for KvV2 {
    const SCHEMA: u32 = 2;
    type Op = Op;
    fn apply(&mut self, op: &Op) -> Result<(), String> {
        let mut k = Kv {
            map: std::mem::take(&mut self.map),
        };
        let r = k.apply(op);
        self.map = k.map;
        r
    }
}

const KEY: &[u8] = b"test-hmac-key-0123456789abcdef!!";

fn dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-state-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

fn wal(d: &PathBuf) -> PathBuf {
    let mut v: Vec<_> = std::fs::read_dir(d)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "wyw"))
        .collect();
    v.sort();
    v.pop().unwrap()
}

#[test]
fn apply_reopen_and_reject() {
    let d = dir("basic");
    {
        let mut s = Store::<Kv>::open(&d, KEY).unwrap();
        s.apply(Op::Put("a".into(), 1)).unwrap();
        s.apply(Op::Put("b".into(), 2)).unwrap();
        assert!(matches!(
            s.apply(Op::Del("zz".into())),
            Err(StateError::Rejected(_))
        ));
        s.apply(Op::Del("a".into())).unwrap();
        assert_eq!(s.lsn(), 3, "rejected op is not logged");
    }
    let s = Store::<Kv>::open(&d, KEY).unwrap();
    assert_eq!(s.lsn(), 3);
    assert_eq!(s.state().map, BTreeMap::from([("b".into(), 2)]));
}

#[test]
fn torn_tail_is_dropped() {
    let d = dir("torn");
    {
        let mut s = Store::<Kv>::open(&d, KEY).unwrap();
        s.apply(Op::Put("a".into(), 1)).unwrap();
        s.apply(Op::Put("b".into(), 2)).unwrap();
    }
    let w = wal(&d);
    let len = std::fs::metadata(&w).unwrap().len();
    // power loss in the middle of the last record
    let f = std::fs::OpenOptions::new().write(true).open(&w).unwrap();
    f.set_len(len - 3).unwrap();
    drop(f);
    let mut s = Store::<Kv>::open(&d, KEY).unwrap();
    assert_eq!(s.lsn(), 1);
    assert_eq!(s.state().map.len(), 1);
    // the store keeps working after truncation
    s.apply(Op::Put("c".into(), 3)).unwrap();
    drop(s);
    let s = Store::<Kv>::open(&d, KEY).unwrap();
    assert_eq!(s.lsn(), 2);
    assert!(s.state().map.contains_key("c"));
}

#[test]
fn edited_record_is_tampering() {
    let d = dir("tamper");
    {
        let mut s = Store::<Kv>::open(&d, KEY).unwrap();
        s.apply(Op::Put("a".into(), 1)).unwrap();
        s.apply(Op::Put("b".into(), 2)).unwrap();
    }
    let w = wal(&d);
    let mut bytes = std::fs::read(&w).unwrap();
    // change the value of the first record and fix its CRC
    let len = u32::from_le_bytes(bytes[0..4].try_into().unwrap()) as usize;
    let payload = 40..40 + len;
    let last = payload.end - 1;
    bytes[last] ^= 0x01;
    let crc = crc32c::crc32c(&bytes[payload]);
    bytes[4..8].copy_from_slice(&crc.to_le_bytes());
    std::fs::write(&w, bytes).unwrap();
    assert!(matches!(
        Store::<Kv>::open(&d, KEY),
        Err(StateError::Tampered { lsn: 1, .. })
    ));
    // a wrong key is caught the same way
    assert!(matches!(
        Store::<Kv>::open(&d, b"other key"),
        Err(StateError::Tampered { .. })
    ));
}

#[test]
fn snapshot_then_more_ops() {
    let d = dir("snap");
    {
        let mut s = Store::<Kv>::open(&d, KEY).unwrap().with_snapshot_every(3);
        for i in 0..7 {
            s.apply(Op::Put(format!("k{i}"), i)).unwrap();
        }
    }
    assert!(d.join("CURRENT").exists());
    let s = Store::<Kv>::open(&d, KEY).unwrap();
    assert_eq!(s.lsn(), 7);
    assert_eq!(s.state().map.len(), 7);
    drop(s);
    // new schema: snapshot ignored, rebuilt from the full WAL
    let v2 = Store::<KvV2>::open(&d, KEY).unwrap();
    assert_eq!(v2.lsn(), 7);
    assert_eq!(v2.state().map.len(), 7);
}

#[test]
fn one_writer_per_store() {
    let d = dir("lock");
    let a = Store::<Kv>::open(&d, KEY).unwrap();
    let e = Store::<Kv>::open(&d, KEY)
        .err()
        .expect("second open refused");
    assert!(matches!(e, StateError::InUse(_)), "{e}");
    drop(a);
    assert!(Store::<Kv>::open(&d, KEY).is_ok(), "free again after drop");
}

fn copy_dir(from: &std::path::Path, to: &std::path::Path) {
    let _ = std::fs::remove_dir_all(to);
    std::fs::create_dir_all(to).unwrap();
    for e in std::fs::read_dir(from).unwrap() {
        let e = e.unwrap();
        if e.file_name() != "LOCK" {
            std::fs::copy(e.path(), to.join(e.file_name())).unwrap();
        }
    }
}

/// T11: the HMAC chain cannot see records cut from the end; an anchor kept
/// outside the store can.
#[test]
fn anchor_detects_a_cut_wal() {
    let d = dir("anchor");
    let backup = dir("anchor-backup");
    let anchor_dir = dir("anchor-head");
    std::fs::create_dir_all(&anchor_dir).unwrap();
    let anchor = anchor_dir.join("state.head");
    {
        let mut s = Store::<Kv>::open(&d, KEY)
            .unwrap()
            .with_anchor(&anchor)
            .unwrap();
        s.apply(Op::Put("a".into(), 1)).unwrap();
        s.apply(Op::Put("b".into(), 2)).unwrap();
    }
    copy_dir(&d, &backup); // two records
    {
        let mut s = Store::<Kv>::open(&d, KEY)
            .unwrap()
            .with_anchor(&anchor)
            .unwrap();
        s.apply(Op::Put("c".into(), 3)).unwrap();
        assert_eq!(s.lsn(), 3);
    }
    // normal reopen with the anchor
    drop(
        Store::<Kv>::open(&d, KEY)
            .unwrap()
            .with_anchor(&anchor)
            .unwrap(),
    );
    // the attacker rolls the store back to two records: refused
    let e = Store::<Kv>::open(&backup, KEY)
        .unwrap()
        .with_anchor(&anchor)
        .err()
        .expect("cut WAL refused");
    assert!(matches!(e, StateError::Anchor { .. }), "{e}");
    // an anchor one record behind (crash between WAL and anchor) is accepted
    std::fs::write(&anchor, format!("2 {}\n", "00".repeat(32))).unwrap();
    assert!(Store::<Kv>::open(&d, KEY)
        .unwrap()
        .with_anchor(&anchor)
        .is_ok());
    // a deleted anchor is not silently recreated for a store with records
    std::fs::remove_file(&anchor).unwrap();
    let e = Store::<Kv>::open(&d, KEY)
        .unwrap()
        .with_anchor(&anchor)
        .err()
        .expect("missing anchor refused");
    assert!(matches!(e, StateError::Anchor { .. }), "{e}");
    // the explicit operator step creates it again
    drop(
        Store::<Kv>::open(&d, KEY)
            .unwrap()
            .init_anchor(&anchor)
            .unwrap(),
    );
    assert!(Store::<Kv>::open(&d, KEY)
        .unwrap()
        .with_anchor(&anchor)
        .is_ok());
}

#[test]
fn verify_reports_without_changing() {
    let d = dir("verify");
    let heads = dir("verify-heads");
    std::fs::create_dir_all(&heads).unwrap();
    let anchor = heads.join("v.head");
    {
        let mut s = Store::<Kv>::open(&d, KEY)
            .unwrap()
            .with_anchor(&anchor)
            .unwrap();
        for i in 0..3 {
            s.apply(Op::Put(format!("k{i}"), i)).unwrap();
        }
        // held by a process: refused
        assert!(matches!(
            wyrm_state::verify(&d, KEY, Some(&anchor)),
            Err(StateError::InUse(_))
        ));
    }
    let r = wyrm_state::verify(&d, KEY, Some(&anchor)).unwrap();
    assert_eq!(
        (r.records, r.last_lsn, r.torn_tail, r.anchor_ok),
        (3, 3, false, Some(true))
    );
    // a wrong key shows tampering
    assert!(matches!(
        wyrm_state::verify(&d, b"another-key-0123456789abcdef!!!!", None),
        Err(StateError::Tampered { .. })
    ));
    // an anchor ahead of the WAL is reported
    std::fs::write(&anchor, format!("9 {}\n", "00".repeat(32))).unwrap();
    assert_eq!(
        wyrm_state::verify(&d, KEY, Some(&anchor))
            .unwrap()
            .anchor_ok,
        Some(false)
    );
}

fn puts(from: u32, n: u32) -> Vec<Op> {
    (from..from + n)
        .map(|i| Op::Put(format!("k{i}"), i))
        .collect()
}

/// Group commit changes when the `fsync` happens, not what is written: a batch is
/// byte for byte the records that single applies write.
#[test]
fn a_batch_writes_the_bytes_of_single_applies() {
    let (one, many) = (dir("bytes-one"), dir("bytes-many"));
    {
        let mut s = Store::<Kv>::open(&one, KEY).unwrap();
        for op in puts(0, 7) {
            s.apply(op).unwrap();
        }
        s.apply(Op::Del("k3".into())).unwrap();
    }
    {
        let mut s = Store::<Kv>::open(&many, KEY).unwrap();
        let lsns: Vec<u64> = s
            .apply_batch(&puts(0, 2))
            .into_iter()
            .map(Result::unwrap)
            .collect();
        assert_eq!(lsns, [1, 2]);
        let mut ops = puts(2, 5);
        ops.push(Op::Del("k3".into()));
        let lsns: Vec<u64> = s
            .apply_batch(&ops)
            .into_iter()
            .map(Result::unwrap)
            .collect();
        assert_eq!(lsns, [3, 4, 5, 6, 7, 8]);
        assert_eq!(s.lsn(), 8);
        assert!(s.apply_batch(&[]).is_empty());
    }
    assert_eq!(
        std::fs::read(wal(&one)).unwrap(),
        std::fs::read(wal(&many)).unwrap()
    );
    let a = Store::<Kv>::open(&one, KEY).unwrap();
    let b = Store::<Kv>::open(&many, KEY).unwrap();
    assert_eq!(a.state(), b.state());
}

/// A rejected op of a batch is answered alone; the others are written in order.
#[test]
fn a_batch_rejects_one_op_alone() {
    let d = dir("batch-reject");
    {
        let mut s = Store::<Kv>::open(&d, KEY).unwrap();
        let r = s.apply_batch(&[
            Op::Put("a".into(), 1),
            Op::Del("zz".into()),
            Op::Put("b".into(), 2),
            Op::Del("a".into()),
            Op::Del("a".into()),
        ]);
        assert_eq!(r.len(), 5);
        assert!(matches!(r[0], Ok(1)));
        assert!(matches!(r[1], Err(StateError::Rejected(_))));
        assert!(matches!(r[2], Ok(2)));
        assert!(matches!(r[3], Ok(3)));
        assert!(matches!(r[4], Err(StateError::Rejected(_))));
        assert_eq!(s.state().map, BTreeMap::from([("b".into(), 2)]));
        // nothing accepted: nothing written
        let r = s.apply_batch(&[Op::Del("zz".into())]);
        assert!(matches!(r[0], Err(StateError::Rejected(_))));
        assert_eq!(s.lsn(), 3);
    }
    let s = Store::<Kv>::open(&d, KEY).unwrap();
    assert_eq!(s.lsn(), 3);
    assert_eq!(s.state().map, BTreeMap::from([("b".into(), 2)]));
    drop(s);
    assert_eq!(wyrm_state::verify(&d, KEY, None).unwrap().records, 3);
}

/// More ops than one batch holds, and snapshots between batches.
#[test]
fn long_batches_and_snapshots() {
    let d = dir("batch-long");
    let n = wyrm_state::MAX_BATCH as u32 + 5;
    {
        let mut s = Store::<Kv>::open(&d, KEY).unwrap().with_snapshot_every(300);
        let r = s.apply_batch(&puts(0, n));
        assert_eq!(r.len(), n as usize);
        for (i, r) in r.iter().enumerate() {
            assert_eq!(*r.as_ref().unwrap(), i as u64 + 1);
        }
        s.apply(Op::Del("k0".into())).unwrap();
        assert!(matches!(s.apply_batch(&puts(n, 3))[2], Ok(l) if l == u64::from(n) + 4));
    }
    assert!(
        d.join("CURRENT").exists(),
        "a batch counts towards snapshots"
    );
    let s = Store::<Kv>::open(&d, KEY).unwrap();
    assert_eq!(s.lsn(), u64::from(n) + 4);
    assert_eq!(s.state().map.len(), n as usize + 2);
    drop(s);
    let r = wyrm_state::verify(&d, KEY, None).unwrap();
    assert_eq!((r.records, r.torn_tail), (u64::from(n) + 4, false));
}

/// A crash anywhere while a batch is written (the WAL cut at every byte of the
/// batch, the anchor as it was written before the batch) leaves a store that opens
/// with a whole prefix of the batch and a chain that verifies.
#[test]
fn a_crash_inside_a_batch_leaves_a_valid_prefix() {
    let d = dir("batch-crash");
    let heads = dir("batch-crash-heads");
    std::fs::create_dir_all(&heads).unwrap();
    let anchor = heads.join("s.head");
    let before_batch;
    let base;
    {
        let mut s = Store::<Kv>::open(&d, KEY)
            .unwrap()
            .with_anchor(&anchor)
            .unwrap();
        s.apply(Op::Put("a".into(), 1)).unwrap();
        s.apply(Op::Put("b".into(), 2)).unwrap();
        before_batch = std::fs::read_to_string(&anchor).unwrap();
        base = std::fs::metadata(wal(&d)).unwrap().len() as usize;
        for r in s.apply_batch(&puts(0, 5)) {
            r.unwrap();
        }
        assert_eq!(s.lsn(), 7);
    }
    // after the batch the anchor is the plain head again
    let after_batch = std::fs::read_to_string(&anchor).unwrap();
    assert_eq!(after_batch.split_whitespace().count(), 2, "{after_batch}");
    assert!(after_batch.starts_with("7 "));
    // what the batch wrote into the anchor first
    let announced = format!("{} +5\n", before_batch.trim_end());
    let full = std::fs::read(wal(&d)).unwrap();
    let name = wal(&d).file_name().unwrap().to_owned();
    // the end of every whole record of the batch
    let mut ends = Vec::new();
    let mut off = base;
    while off < full.len() {
        let len = u32::from_le_bytes(full[off..off + 4].try_into().unwrap()) as usize;
        off += 40 + len;
        ends.push(off);
    }
    assert_eq!(ends.len(), 5);
    let crash = dir("batch-crash-copy");
    let crash_anchor = heads.join("copy.head");
    for cut in base..=full.len() {
        copy_dir(&d, &crash);
        std::fs::write(crash.join(&name), &full[..cut]).unwrap();
        std::fs::write(&crash_anchor, &announced).unwrap();
        let whole = ends.iter().filter(|e| **e <= cut).count() as u64;
        let torn = cut != base && !ends.contains(&cut);
        let r = wyrm_state::verify(&crash, KEY, Some(&crash_anchor)).unwrap();
        assert_eq!(
            (r.records, r.torn_tail, r.anchor_ok),
            (2 + whole, torn, Some(true)),
            "cut at {cut}"
        );
        let mut s = Store::<Kv>::open(&crash, KEY)
            .unwrap()
            .with_anchor(&crash_anchor)
            .unwrap_or_else(|e| panic!("cut at {cut}: {e}"));
        assert_eq!(s.lsn(), 2 + whole, "cut at {cut}");
        assert_eq!(s.state().map.len(), 2 + whole as usize, "cut at {cut}");
        // open put the anchor at the head, and the store goes on
        if cut % 37 == 0 || cut == full.len() {
            s.apply(Op::Put("after".into(), 9)).unwrap();
            drop(s);
            let r = wyrm_state::verify(&crash, KEY, Some(&crash_anchor)).unwrap();
            assert_eq!((r.records, r.anchor_ok), (3 + whole, Some(true)));
        }
    }
    // a byte changed inside the batch is still found
    let mut bad = full.clone();
    bad[ends[1] + 45] ^= 1;
    copy_dir(&d, &crash);
    std::fs::write(crash.join(&name), &bad).unwrap();
    assert!(Store::<Kv>::open(&crash, KEY).is_err());
}

/// The announcement of a batch does not weaken the anchor: without it more than
/// one record after the anchor is refused as before, with it no more than the
/// batch may follow, and a finished batch leaves no allowance behind.
#[test]
fn the_anchor_of_a_batch_refuses_every_other_cut() {
    let d = dir("batch-anchor");
    let heads = dir("batch-anchor-heads");
    std::fs::create_dir_all(&heads).unwrap();
    let anchor = heads.join("s.head");
    let at2;
    {
        let mut s = Store::<Kv>::open(&d, KEY)
            .unwrap()
            .with_anchor(&anchor)
            .unwrap();
        s.apply(Op::Put("a".into(), 1)).unwrap();
        s.apply(Op::Put("b".into(), 2)).unwrap();
        at2 = std::fs::read_to_string(&anchor).unwrap();
    }
    let at2 = at2.trim_end();
    let two = dir("batch-anchor-two");
    copy_dir(&d, &two);
    {
        let mut s = Store::<Kv>::open(&d, KEY)
            .unwrap()
            .with_anchor(&anchor)
            .unwrap();
        for r in s.apply_batch(&puts(0, 5)) {
            r.unwrap();
        }
    }
    // does a store in `dir` open with an anchor of this text? (`verify` must agree)
    let opens = |dir: &PathBuf, text: &str| {
        let a = heads.join("try.head");
        std::fs::write(&a, text).unwrap();
        let ok = wyrm_state::verify(dir, KEY, Some(&a)).unwrap().anchor_ok;
        let opened = Store::<Kv>::open(dir, KEY).unwrap().with_anchor(&a).is_ok();
        assert_eq!(ok, Some(opened), "verify and open agree on {text:?}");
        opened
    };
    // the batch is whole and the anchor is at it: the store cut back to two is refused
    let at7 = std::fs::read_to_string(&anchor).unwrap();
    assert!(!opens(&two, &at7));
    // an anchor five behind with no announcement: refused, as before group commit
    assert!(!opens(&d, &format!("{at2}\n")));
    // announced: five may follow, four may not
    assert!(opens(&d, &format!("{at2} +5\n")));
    assert!(!opens(&d, &format!("{at2} +4\n")));
    // junk is not read as an announcement
    assert!(!opens(&d, &format!("{at2} 5\n")));
    assert!(!opens(&d, &format!("{at2} +x\n")));
    // the same head with another MAC stays an error whatever is announced
    assert!(!opens(&d, &format!("7 {} +5\n", "00".repeat(32))));
    // an announcement is no licence beyond one batch
    assert!(opens(&d, &format!("{at2} +99999999\n")));
    {
        let mut s = Store::<Kv>::open(&d, KEY).unwrap();
        for r in s.apply_batch(&puts(100, wyrm_state::MAX_BATCH as u32)) {
            r.unwrap();
        }
    }
    assert!(!opens(&d, &format!("{at2} +99999999\n")));
}

use std::sync::{Arc, Mutex};
use wyrm_state::{Fault, Step};

/// What the next append meets: a failure at one step, set by the test.
type Plan = Arc<Mutex<Vec<(Step, bool)>>>;

/// A store whose appends fail at the steps of `plan` (`true`: a torn write).
fn failing(d: &PathBuf, anchor: Option<&PathBuf>, plan: &Plan) -> Store<Kv> {
    let mut s = Store::<Kv>::open(d, KEY).unwrap();
    if let Some(a) = anchor {
        s = s.with_anchor(a).unwrap();
    }
    let plan = plan.clone();
    s.with_probe(Box::new(move |step| {
        let mut p = plan.lock().unwrap();
        match p.iter().position(|(s, _)| *s == step) {
            Some(i) => {
                let (_, torn) = p.remove(i);
                let e = std::io::Error::other(format!("injected at {step:?}"));
                Err(if torn { Fault::Torn(e) } else { Fault::Fail(e) })
            }
            None => Ok(()),
        }
    }))
}

fn wal_len(d: &PathBuf) -> u64 {
    std::fs::metadata(wal(d)).unwrap().len()
}

/// The pre-group-commit rule of the anchor, as every version before
/// `apply_batch` reads it: two fields, at most one record after the head.
fn old_rule_accepts(dir: &std::path::Path, anchor: &std::path::Path) -> bool {
    let r = wyrm_state::verify(dir, KEY, None).unwrap();
    let text = std::fs::read_to_string(anchor).unwrap();
    let mut it = text.split_whitespace();
    let lsn: u64 = it.next().unwrap().parse().unwrap();
    lsn <= r.last_lsn && lsn + 1 >= r.last_lsn
}

/// The files as a kill at each step of a real batch leaves them: the store opens
/// with a whole prefix. The batch itself wrote the announcement (not the test):
/// with the same files and the plain head, the open is refused.
#[test]
fn a_kill_at_each_step_of_a_batch_leaves_a_store_that_opens() {
    let d = dir("kill-steps");
    let heads = dir("kill-steps-heads");
    std::fs::create_dir_all(&heads).unwrap();
    let anchor = heads.join("s.head");
    let seen: Arc<Mutex<Vec<(Step, PathBuf, String)>>> = Arc::default();
    let mut s = Store::<Kv>::open(&d, KEY)
        .unwrap()
        .with_anchor(&anchor)
        .unwrap();
    s.apply(Op::Put("a".into(), 1)).unwrap();
    s.apply(Op::Put("b".into(), 2)).unwrap();
    let plain = std::fs::read_to_string(&anchor).unwrap();
    let (d2, a2, seen2) = (d.clone(), anchor.clone(), seen.clone());
    let mut s = s.with_probe(Box::new(move |step| {
        // the files as they are now: what a kill before this step leaves
        let copy = dir(&format!("kill-steps-at-{step:?}"));
        copy_dir(&d2, &copy);
        let text = std::fs::read_to_string(&a2).unwrap();
        seen2.lock().unwrap().push((step, copy, text));
        Ok(())
    }));
    for r in s.apply_batch(&puts(0, 5)) {
        r.unwrap();
    }
    drop(s);
    let seen = std::mem::take(&mut *seen.lock().unwrap());
    let steps: Vec<Step> = seen.iter().map(|(s, _, _)| *s).collect();
    assert_eq!(
        steps,
        [Step::Announce, Step::Write, Step::Sync, Step::Anchor]
    );
    let announced = format!("{} +5\n", plain.trim_end());
    for (step, copy, text) in &seen {
        // records in the WAL at that moment, and the anchor beside it
        let (records, want_anchor) = match step {
            Step::Announce => (2, &plain),
            Step::Write => (2, &announced),
            _ => (7, &announced),
        };
        assert_eq!(text, want_anchor, "{step:?}");
        let a = heads.join(format!("{step:?}.head"));
        std::fs::write(&a, text).unwrap();
        let v = wyrm_state::verify(copy, KEY, Some(&a)).unwrap();
        assert_eq!((v.records, v.anchor_ok), (records, Some(true)), "{step:?}");
        let s = Store::<Kv>::open(copy, KEY)
            .unwrap()
            .with_anchor(&a)
            .unwrap_or_else(|e| panic!("a kill before {step:?}: {e}"));
        assert_eq!(s.lsn(), records, "{step:?}");
        drop(s);
        // the announcement is what lets it open: the plain head does not
        if records == 7 {
            std::fs::write(&a, &plain).unwrap();
            assert!(
                Store::<Kv>::open(copy, KEY)
                    .unwrap()
                    .with_anchor(&a)
                    .is_err(),
                "{step:?}: five records after a plain head"
            );
            assert!(!old_rule_accepts(copy, &a));
        }
    }
    // a batch of one announces nothing: its files pass the old rule at every step
    let seen: Arc<Mutex<Vec<bool>>> = Arc::default();
    let (d2, a2, seen2) = (d.clone(), anchor.clone(), seen.clone());
    let mut s = Store::<Kv>::open(&d, KEY)
        .unwrap()
        .with_anchor(&anchor)
        .unwrap()
        .with_probe(Box::new(move |step| {
            let copy = dir("kill-steps-one");
            copy_dir(&d2, &copy);
            let text = std::fs::read_to_string(&a2).unwrap();
            assert_eq!(text.split_whitespace().count(), 2, "{step:?}: {text}");
            seen2.lock().unwrap().push(old_rule_accepts(&copy, &a2));
            Ok(())
        }));
    s.apply_batch(&puts(50, 1)).remove(0).unwrap();
    s.apply(Op::Put("z".into(), 1)).unwrap();
    assert_eq!(*seen.lock().unwrap(), [true; 6]);
}

/// A step of a batch fails: every op of the batch is answered with the error, the
/// head and the state do not move, nothing of the batch stays in the WAL, and the
/// store goes on (or says that it does not).
#[test]
fn a_failed_batch_leaves_no_bytes_and_moves_nothing() {
    for (step, torn) in [
        (Step::Announce, false),
        (Step::Write, false),
        (Step::Write, true),
    ] {
        let name = format!("fail-{step:?}-{torn}");
        let d = dir(&name);
        let heads = dir(&format!("{name}-heads"));
        std::fs::create_dir_all(&heads).unwrap();
        let anchor = heads.join("s.head");
        let plan = Plan::default();
        let mut s = failing(&d, Some(&anchor), &plan);
        s.apply(Op::Put("a".into(), 1)).unwrap();
        let (len, head) = (wal_len(&d), std::fs::read_to_string(&anchor).unwrap());
        plan.lock().unwrap().push((step, torn));
        let r = s.apply_batch(&[
            Op::Put("b".into(), 2),
            Op::Del("zz".into()),
            Op::Put("c".into(), 3),
        ]);
        assert!(matches!(r[0], Err(StateError::Io(_))), "{name}: {:?}", r[0]);
        assert!(matches!(r[1], Err(StateError::Rejected(_))), "{name}");
        assert!(matches!(r[2], Err(StateError::Io(_))), "{name}");
        assert_eq!(s.lsn(), 1, "{name}");
        assert_eq!(s.state().map.len(), 1, "{name}");
        assert_eq!(wal_len(&d), len, "{name}: bytes left in the WAL");
        // the announcement did not outlive the batch
        assert_eq!(std::fs::read_to_string(&anchor).unwrap(), head, "{name}");
        // the store goes on, and the next records follow the old head
        let r = s.apply_batch(&puts(0, 3));
        assert!(matches!(r[2], Ok(4)), "{name}: {r:?}");
        assert_eq!(s.apply(Op::Put("d".into(), 4)).unwrap(), 5, "{name}");
        drop(s);
        let v = wyrm_state::verify(&d, KEY, Some(&anchor)).unwrap();
        assert_eq!(
            (v.records, v.torn_tail, v.anchor_ok),
            (5, false, Some(true)),
            "{name}"
        );
        let s = Store::<Kv>::open(&d, KEY)
            .unwrap()
            .with_anchor(&anchor)
            .unwrap();
        assert_eq!(s.state().map.len(), 5, "{name}");
    }
}

/// The same for one record through `apply`: a torn write is cut back.
#[test]
fn a_failed_apply_leaves_no_bytes() {
    let d = dir("fail-apply");
    let plan = Plan::default();
    let mut s = failing(&d, None, &plan);
    s.apply(Op::Put("a".into(), 1)).unwrap();
    let len = wal_len(&d);
    plan.lock().unwrap().push((Step::Write, true));
    assert!(matches!(
        s.apply(Op::Put("b".into(), 2)),
        Err(StateError::Io(_))
    ));
    assert_eq!((s.lsn(), wal_len(&d)), (1, len));
    assert_eq!(s.apply(Op::Put("c".into(), 3)).unwrap(), 2);
    drop(s);
    // before the cut, the half record stayed and the next one followed it: the
    // start then read a broken log
    let s = Store::<Kv>::open(&d, KEY).unwrap();
    assert_eq!(s.lsn(), 2);
    assert!(s.state().map.contains_key("c") && !s.state().map.contains_key("b"));
}

/// When the WAL cannot be put back (the cut fails), or the `fsync` failed, the
/// store refuses every later write by name; nothing is appended after bytes it
/// does not know. A new open reads the file: a whole prefix, no broken chain.
#[test]
fn a_store_that_cannot_undo_a_write_takes_no_more() {
    for (fails, batch) in [
        (vec![(Step::Sync, false)], true),
        (vec![(Step::Write, true), (Step::Cut, false)], true),
        (vec![(Step::Sync, false)], false),
        (vec![(Step::Write, true), (Step::Cut, false)], false),
    ] {
        let name = format!("broken-{}-{batch}", fails.len());
        let d = dir(&name);
        let heads = dir(&format!("{name}-heads"));
        std::fs::create_dir_all(&heads).unwrap();
        let anchor = heads.join("s.head");
        let plan = Plan::default();
        let mut s = failing(&d, Some(&anchor), &plan);
        s.apply(Op::Put("a".into(), 1)).unwrap();
        *plan.lock().unwrap() = fails.clone();
        if batch {
            let r = s.apply_batch(&puts(0, 5));
            assert!(
                r.iter().all(|r| matches!(r, Err(StateError::Io(_)))),
                "{name}"
            );
        } else {
            assert!(matches!(
                s.apply(Op::Put("b".into(), 2)),
                Err(StateError::Io(_))
            ));
        }
        assert_eq!(s.lsn(), 1, "{name}");
        assert_eq!(s.state().map.len(), 1, "{name}");
        let len = wal_len(&d);
        // every later write is refused, and writes nothing
        assert!(matches!(
            s.apply(Op::Put("x".into(), 9)),
            Err(StateError::Broken(_))
        ));
        let r = s.apply_batch(&puts(10, 2));
        assert!(
            r.iter().all(|r| matches!(r, Err(StateError::Broken(_)))),
            "{name}: {r:?}"
        );
        assert_eq!((s.lsn(), wal_len(&d)), (1, len), "{name}");
        drop(s);
        // a new open: what was torn is dropped, whole records of the unanswered
        // batch may be there, the chain holds, the anchor accepts it
        let v = wyrm_state::verify(&d, KEY, Some(&anchor)).unwrap();
        assert_eq!(v.anchor_ok, Some(true), "{name}");
        let mut s = Store::<Kv>::open(&d, KEY)
            .unwrap()
            .with_anchor(&anchor)
            .unwrap_or_else(|e| panic!("{name}: {e}"));
        assert!((1..=6).contains(&s.lsn()), "{name}: {}", s.lsn());
        let n = s.lsn();
        assert_eq!(
            s.apply(Op::Put("after".into(), 1)).unwrap(),
            n + 1,
            "{name}"
        );
        drop(s);
        let v = wyrm_state::verify(&d, KEY, Some(&anchor)).unwrap();
        assert_eq!((v.records, v.torn_tail), (n + 1, false), "{name}");
    }
}
