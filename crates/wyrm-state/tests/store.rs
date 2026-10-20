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
