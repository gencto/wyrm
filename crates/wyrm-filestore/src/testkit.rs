//! The end-to-end scenario every store link runs against its simulator
//! (feature `testkit`): the tree, folders, uploads, downloads, deletes,
//! refreshes, edits that keep secrets, stop and start.
//!
//! Before the link starts, the store holds [`SEED`]; the link has one
//! connection `c1`.

use crate::store::{ENTRIES, FILES};
use crate::{Backend, FileStore};
use std::time::Duration;
use wyrm_core::status::StatusCode;
use wyrm_core::{Attachment, NodeMeta, Perm, Status, Value};
use wyrm_link_sdk::driver::NodeState;
use wyrm_link_sdk::TestHarness;

pub type H<B> = TestHarness<FileStore<B>>;

/// Files in the store when the scenario starts (folders implied).
pub const SEED: &[(&str, &str)] = &[
    ("reports/2026/october.csv", "day,energy\n1,120\n"),
    ("reports/readme.txt", "monthly reports\n"),
    ("config/plant.json", "{\"units\": 4}\n"),
    ("a b (1).txt", "spaces\n"),
];
/// Entries of [`SEED`]: 4 files, 3 folders.
pub const SEED_ENTRIES: u64 = 7;

/// A change made in the store behind the link's back.
pub enum Ext<'a> {
    Put(&'a str, &'a [u8]),
    Delete(&'a str),
}

pub fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// Bootstrap params with one connection `c1`.
pub fn bootstrap(conn: Value) -> crate::Bootstrap {
    bootstrap_with(conn, &[])
}

/// Bootstrap params with one connection `c1` and link options.
pub fn bootstrap_with(conn: Value, options: &[(&str, Value)]) -> crate::Bootstrap {
    let mut kv = vec![("connections", map(&[("c1", conn)]))];
    kv.extend(options.iter().cloned());
    crate::Bootstrap(map(&kv))
}

pub fn state<B: Backend>(h: &H<B>, conn: &str) -> Option<&'static str> {
    match h.ctx().last(&format!("{conn}/status"))?.v {
        Value::UInt(i) => NodeState::NAMES.get(i as usize).copied(),
        _ => None,
    }
}

pub fn error<B: Backend>(h: &H<B>, conn: &str) -> Option<String> {
    match h.ctx().last(&format!("{conn}/error"))?.v {
        Value::Str(s) => Some(s),
        _ => None,
    }
}

pub async fn wait(what: &str, secs: u64, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(secs);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

pub fn status(a: &Attachment) -> Status {
    match a.status {
        Some(StatusCode::Known(s)) => s,
        None => Status::Ok,
        Some(other) => panic!("unknown status {other:?}"),
    }
}

/// Invoke at `config` and return the attachment and the value.
pub async fn act<B: Backend>(
    h: &H<B>,
    path: &str,
    action: &str,
    args: Value,
) -> (Attachment, Option<Value>) {
    let mut r = h
        .invoke(path, action, args, Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(r.len(), 1, "{path} {action}: one reply");
    let r = r.remove(0);
    let v = r.value();
    (r.att, v)
}

pub async fn ok<B: Backend>(h: &H<B>, path: &str, action: &str, args: Value) -> Option<Value> {
    let (a, v) = act(h, path, action, args).await;
    assert_eq!(status(&a), Status::Ok, "{path} {action}: {:?}", a.err);
    v
}

fn get<'a>(v: &'a Option<Value>, k: &str) -> &'a Value {
    match v {
        Some(Value::Map(m)) => m.get(k).unwrap_or(&Value::Null),
        _ => &Value::Null,
    }
}

/// The child of `parent` that people see as `name`: its key and meta.
pub async fn child<B: Backend>(h: &H<B>, parent: &str, name: &str) -> Option<(String, NodeMeta)> {
    let (_, m) = h.meta(parent).await;
    for c in m?.children.unwrap_or_default() {
        let key = format!("{parent}/{c}");
        let (_, cm) = h.meta(&key).await;
        if let Some(cm) = cm.filter(|cm| cm.attr_value("display") == Some(&Value::Str(name.into())))
        {
            return Some((key, cm));
        }
    }
    None
}

fn entries<B: Backend>(h: &H<B>) -> u64 {
    h.ctx()
        .last(&format!("c1/{ENTRIES}"))
        .and_then(|s| match s.v {
            Value::UInt(n) => Some(n),
            _ => None,
        })
        .unwrap_or(0)
}

/// The scenario. `ext` changes the store directly.
pub async fn scenario<B: Backend>(h: &H<B>, ext: &dyn Fn(Ext<'_>)) {
    let files = format!("c1/{FILES}");
    wait("connected", 10, || state(h, "c1") == Some("connected")).await;
    wait("seed shown", 10, || entries(h) == SEED_ENTRIES).await;

    // the tree, names for people, the weird name made safe
    let (reports, m) = child(h, &files, "reports").await.expect("reports");
    assert!(m.actions.as_ref().unwrap().contains_key("upload"));
    let (y2026, _) = child(h, &reports, "2026").await.expect("2026");
    let (oct, m) = child(h, &y2026, "october.csv").await.expect("october.csv");
    assert_eq!(
        m.attr_value("path"),
        Some(&Value::Str("reports/2026/october.csv".into()))
    );
    assert_eq!(
        h.ctx().last(&oct).map(|s| s.v),
        Some(Value::UInt(SEED[0].1.len() as u64))
    );
    let (weird, _) = child(h, &files, "a b (1).txt").await.expect("weird name");
    assert!(wyrm_core::keyspace::validate_path(&weird).is_ok());

    // download, as text and as bytes
    let v = ok(h, &oct, "download", map(&[("text", Value::Bool(true))])).await;
    assert_eq!(v, Some(Value::Str(SEED[0].1.into())));
    let v = ok(h, &weird, "download", map(&[])).await;
    assert_eq!(v, Some(Value::Bytes(SEED[3].1.as_bytes().to_vec())));

    // create a folder, upload into it, refuse a second upload of that name
    let v = ok(
        h,
        &reports,
        "create_folder",
        map(&[("name", "new dir".into())]),
    )
    .await;
    assert_eq!(get(&v, "path"), &Value::Str("reports/new dir".into()));
    let (newdir, _) = child(h, &reports, "new dir").await.expect("new dir shown");
    let (a, _) = act(
        h,
        &reports,
        "create_folder",
        map(&[("name", "new dir".into())]),
    )
    .await;
    assert_eq!(status(&a), Status::InvalidParameter, "the folder exists");
    let (a, _) = act(h, &reports, "create_folder", map(&[("name", "a/b".into())])).await;
    assert_eq!(status(&a), Status::InvalidParameter, "no / in names");

    let body = b"{\"ok\": true}\n".to_vec();
    let v = ok(
        h,
        &newdir,
        "upload",
        map(&[
            ("name", "data.json".into()),
            ("file", Value::Bytes(body.clone())),
        ]),
    )
    .await;
    assert_eq!(get(&v, "size"), &Value::UInt(body.len() as u64));
    let (data, m) = child(h, &newdir, "data.json")
        .await
        .expect("uploaded file shown");
    assert_eq!(
        m.attr_value("content_type"),
        Some(&Value::Str("application/json".into()))
    );
    let (a, _) = act(
        h,
        &newdir,
        "upload",
        map(&[("name", "data.json".into()), ("text", "x".into())]),
    )
    .await;
    assert_eq!(
        status(&a),
        Status::InvalidParameter,
        "exists without overwrite"
    );
    ok(
        h,
        &newdir,
        "upload",
        map(&[
            ("name", "data.json".into()),
            ("text", "replaced".into()),
            ("overwrite", Value::Bool(true)),
        ]),
    )
    .await;
    wait("new size", 5, || {
        h.ctx().last(&data).map(|s| s.v) == Some(Value::UInt(8))
    })
    .await;
    let v = ok(h, &data, "download", map(&[("text", Value::Bool(true))])).await;
    assert_eq!(v, Some(Value::Str("replaced".into())));
    // root uploads
    ok(
        h,
        &files,
        "upload",
        map(&[("name", "top.txt".into()), ("text", "top".into())]),
    )
    .await;
    assert!(child(h, &files, "top.txt").await.is_some());
    assert_eq!(entries(h), SEED_ENTRIES + 3);

    // a folder the tree shows empty, with a file in it the tree does not
    // know yet: the store is asked, not the tree
    ok(
        h,
        &reports,
        "create_folder",
        map(&[("name", "ghost".into())]),
    )
    .await;
    let (ghost, _) = child(h, &reports, "ghost").await.expect("ghost shown");
    ext(Ext::Put("reports/ghost/unseen.txt", b"unseen"));
    let (a, _) = act(h, &ghost, "delete", map(&[])).await;
    assert_eq!(
        status(&a),
        Status::InvalidParameter,
        "not empty in the store: {:?}",
        a.err
    );
    assert!(h.ctx().has_node(&ghost), "nothing deleted");
    ok(
        h,
        &ghost,
        "delete",
        map(&[("recursive", Value::Bool(true))]),
    )
    .await;
    assert!(child(h, &reports, "ghost").await.is_none());
    // an empty folder goes without recursive
    ok(
        h,
        &reports,
        "create_folder",
        map(&[("name", "empty".into())]),
    )
    .await;
    let (empty, _) = child(h, &reports, "empty").await.expect("empty shown");
    ok(h, &empty, "delete", map(&[])).await;
    assert!(child(h, &reports, "empty").await.is_none());

    // delete: a file, a folder only with recursive
    let (a, _) = act(h, &newdir, "delete", map(&[])).await;
    assert_eq!(status(&a), Status::InvalidParameter, "not empty");
    ok(
        h,
        &newdir,
        "delete",
        map(&[("recursive", Value::Bool(true))]),
    )
    .await;
    assert!(child(h, &reports, "new dir").await.is_none());
    let (top, _) = child(h, &files, "top.txt").await.unwrap();
    ok(h, &top, "delete", map(&[])).await;
    assert!(child(h, &files, "top.txt").await.is_none());
    assert_eq!(entries(h), SEED_ENTRIES);

    // changes behind the link's back show on a refresh
    ext(Ext::Put("config/extra.ini", b"[a]\n"));
    ext(Ext::Delete("reports/readme.txt"));
    let v = ok(h, "c1", "refresh", map(&[])).await;
    assert_eq!(get(&v, "truncated"), &Value::Bool(false));
    let (config, _) = child(h, &files, "config").await.unwrap();
    assert!(
        child(h, &config, "extra.ini").await.is_some(),
        "a new file shows"
    );
    assert!(
        child(h, &reports, "readme.txt").await.is_none(),
        "a deleted file goes"
    );
    // a folder refresh
    ext(Ext::Put("config/more.ini", b"[b]\n"));
    ok(h, &config, "refresh", map(&[])).await;
    assert!(child(h, &config, "more.ini").await.is_some());
    // the node of a file keeps its key across refreshes
    assert!(h.ctx().has_node(&oct));

    // reads at read, writes at write
    let r = h
        .invoke(
            &files,
            "upload",
            map(&[("name", "x".into()), ("text", "x".into())]),
            Some(h.ptok(Perm::Read)),
        )
        .await;
    assert_eq!(status(&r[0].att), Status::PermissionDenied);
    let r = h
        .invoke(&oct, "download", map(&[]), Some(h.ptok(Perm::Read)))
        .await;
    assert_eq!(status(&r[0].att), Status::Ok);

    // stop removes the tree, start reads it again
    ok(h, "c1", "stop", map(&[])).await;
    wait("stopped", 5, || state(h, "c1") == Some("stopped")).await;
    assert!(!h.ctx().has_node(&files));
    ok(h, "c1", "start", map(&[])).await;
    wait("connected again", 10, || {
        state(h, "c1") == Some("connected")
    })
    .await;
    wait("tree again", 10, || h.ctx().has_node(&oct)).await;

    // an edit that leaves the secrets out keeps them (same destination)
    let (_, m) = h.meta("c1").await;
    let m = m.unwrap();
    let cfg = m.cfg.clone().unwrap_or_default();
    let mut args = cfg.clone();
    args.insert("refresh_s".into(), Value::Float(600.0));
    ok(h, "c1", "edit", Value::Map(args)).await;
    wait("connected after edit", 10, || {
        state(h, "c1") == Some("connected")
    })
    .await;
    let (_, m) = h.meta("c1").await;
    assert_eq!(m.unwrap().cfg.unwrap()["refresh_s"], Value::Float(600.0));
    let secrets: Vec<&str> = crate::store::schema::<B>()
        .iter()
        .filter(|s| s.secret)
        .map(|s| s.name)
        .collect();
    for s in secrets {
        assert!(!cfg.contains_key(s), "secret {s} not shown");
    }
}

/// A store that refuses the credentials: the connection fails with an
/// error leaf, and no tree is declared.
pub async fn refused<B: Backend>(h: &H<B>) {
    wait("failed", 10, || state(h, "c1") == Some("failed")).await;
    assert!(error(h, "c1").is_some());
    let (_, l) = h.list(&format!("c1/{FILES}")).await;
    assert!(l.is_empty());
}

/// Bytes of a test file: not a repeating block, so a part in the wrong
/// place shows.
pub fn big(size: usize) -> Vec<u8> {
    let mut x: u32 = 0x9E37_79B9;
    (0..size)
        .map(|_| {
            x ^= x << 13;
            x ^= x >> 17;
            x ^= x << 5;
            (x >> 24) as u8
        })
        .collect()
}

fn sha_hex(b: &[u8]) -> String {
    use sha2::Digest;
    sha2::Sha256::digest(b)
        .iter()
        .map(|x| format!("{x:02x}"))
        .collect()
}

fn text_of(v: &Option<Value>, k: &str) -> String {
    match get(v, k) {
        Value::Str(s) => s.clone(),
        other => panic!("{k}: {other:?}"),
    }
}

/// Wait until the upload `id` leaves `committing`; its status.
async fn committed<B: Backend>(h: &H<B>, id: &str) -> Option<Value> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(60);
    loop {
        let v = ok(h, "c1", "upload_status", map(&[("upload", id.into())])).await;
        if text_of(&v, "state") != "committing" {
            return v;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "commit took too long"
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

/// Upload `data` to `folder` as `name` in parts of `part` bytes, the last
/// part first; the final status.
pub async fn upload_in_parts<B: Backend>(
    h: &H<B>,
    folder: &str,
    name: &str,
    data: &[u8],
    part: usize,
    extra: &[(&str, Value)],
) -> Option<Value> {
    let mut args = vec![
        ("name", Value::Str(name.into())),
        ("size", Value::UInt(data.len() as u64)),
        ("part_size", Value::UInt(part as u64)),
        ("sha256", Value::Str(sha_hex(data))),
    ];
    args.extend(extra.iter().cloned());
    let v = ok(h, folder, "upload_begin", map(&args)).await;
    let id = text_of(&v, "upload");
    let parts = data.len().div_ceil(part);
    assert_eq!(get(&v, "parts"), &Value::UInt(parts as u64));
    for i in (0..parts).rev() {
        let chunk = &data[i * part..((i + 1) * part).min(data.len())];
        ok(
            h,
            "c1",
            "upload_part",
            map(&[
                ("upload", id.clone().into()),
                ("index", Value::UInt(i as u64)),
                ("data", Value::Bytes(chunk.to_vec())),
            ]),
        )
        .await;
    }
    let v = ok(
        h,
        "c1",
        "upload_status",
        map(&[("upload", id.clone().into())]),
    )
    .await;
    assert_eq!(get(&v, "missing"), &Value::Array(Vec::new()));
    let v = ok(
        h,
        "c1",
        "upload_commit",
        map(&[("upload", id.clone().into())]),
    )
    .await;
    assert_eq!(text_of(&v, "state"), "committing");
    committed(h, &id).await
}

/// Download the file node `file` in parts of `part` bytes.
pub async fn download_in_parts<B: Backend>(h: &H<B>, file: &str, part: usize) -> Vec<u8> {
    let mut out = Vec::new();
    loop {
        let v = ok(
            h,
            file,
            "download_part",
            map(&[
                ("offset", Value::UInt(out.len() as u64)),
                ("length", Value::UInt(part as u64)),
            ]),
        )
        .await;
        match get(&v, "data") {
            Value::Bytes(b) => out.extend_from_slice(b),
            other => panic!("data: {other:?}"),
        }
        if get(&v, "eof") == &Value::Bool(true) {
            return out;
        }
    }
}

/// Uploads and downloads in parts of a file of `size` bytes, after
/// [`scenario`]'s seed is shown.
pub async fn parts_scenario<B: Backend>(h: &H<B>, size: usize) {
    let files = format!("c1/{FILES}");
    wait("connected", 10, || state(h, "c1") == Some("connected")).await;
    let (reports, _) = child(h, &files, "reports").await.expect("reports");
    let data = big(size);
    let part = 1024 * 1024 + 4096; // not a power of two: offsets show
    let v = upload_in_parts(h, &reports, "big.bin", &data, part, &[]).await;
    assert_eq!(text_of(&v, "state"), "done", "{v:?}");
    let (node, m) = child(h, &reports, "big.bin").await.expect("big.bin shown");
    assert_eq!(
        h.ctx().last(&node).map(|s| s.v),
        Some(Value::UInt(size as u64))
    );
    assert!(m.actions.unwrap().contains_key("download_part"));
    let back = download_in_parts(h, &node, 3 * 1024 * 1024 + 1).await;
    assert!(
        back == data,
        "the same bytes back ({} of {size})",
        back.len()
    );
    // a range past the end, an empty one at the end
    let (a, _) = act(
        h,
        &node,
        "download_part",
        map(&[("offset", Value::UInt(size as u64 + 1))]),
    )
    .await;
    assert_eq!(status(&a), Status::OutOfRange);
    let v = ok(
        h,
        &node,
        "download_part",
        map(&[("offset", Value::UInt(size as u64))]),
    )
    .await;
    assert_eq!(get(&v, "eof"), &Value::Bool(true));

    // the name taken: refused at begin without overwrite
    let (a, _) = act(
        h,
        &reports,
        "upload_begin",
        map(&[("name", "big.bin".into()), ("size", Value::UInt(10))]),
    )
    .await;
    assert_eq!(status(&a), Status::InvalidParameter);
    // with overwrite but a wrong digest: the commit fails, the file stays
    let small = big(200_000);
    let v = ok(
        h,
        &reports,
        "upload_begin",
        map(&[
            ("name", "big.bin".into()),
            ("size", Value::UInt(small.len() as u64)),
            ("part_size", Value::UInt(65_536)),
            ("overwrite", Value::Bool(true)),
            ("sha256", Value::Str("00".repeat(32))),
        ]),
    )
    .await;
    let id = text_of(&v, "upload");
    for i in 0..small.len().div_ceil(65_536) {
        let c = &small[i * 65_536..((i + 1) * 65_536).min(small.len())];
        ok(
            h,
            "c1",
            "upload_part",
            map(&[
                ("upload", id.clone().into()),
                ("index", Value::UInt(i as u64)),
                ("data", Value::Bytes(c.to_vec())),
            ]),
        )
        .await;
    }
    ok(
        h,
        "c1",
        "upload_commit",
        map(&[("upload", id.clone().into())]),
    )
    .await;
    let v = committed(h, &id).await;
    assert_eq!(text_of(&v, "state"), "failed");
    assert!(text_of(&v, "error").contains("sha256"));
    assert_eq!(
        h.ctx().last(&node).map(|s| s.v),
        Some(Value::UInt(size as u64))
    );
    // overwrite with the right digest
    let v = upload_in_parts(
        h,
        &reports,
        "big.bin",
        &small,
        65_536,
        &[("overwrite", Value::Bool(true))],
    )
    .await;
    assert_eq!(text_of(&v, "state"), "done", "{v:?}");
    wait("new size", 10, || {
        h.ctx().last(&node).map(|s| s.v) == Some(Value::UInt(small.len() as u64))
    })
    .await;
    assert!(download_in_parts(h, &node, 70_000).await == small);

    // an upload is its owner's; abort drops it; a missing part blocks the commit
    let v = ok(
        h,
        &reports,
        "upload_begin",
        map(&[
            ("name", "x.bin".into()),
            ("size", Value::UInt(100_000)),
            ("part_size", Value::UInt(65_536)),
        ]),
    )
    .await;
    let id = text_of(&v, "upload");
    let mut claims = h.claims(&[(&h.key("**", ""), Perm::Config)]);
    claims.sub = "user:other".into();
    let r = h
        .invoke(
            "c1",
            "upload_status",
            map(&[("upload", id.clone().into())]),
            Some(h.sign(&claims)),
        )
        .await;
    assert_eq!(status(&r[0].att), Status::NotFound, "another's upload");
    let (a, _) = act(
        h,
        "c1",
        "upload_commit",
        map(&[("upload", id.clone().into())]),
    )
    .await;
    assert_eq!(status(&a), Status::InvalidParameter, "parts missing");
    let (a, _) = act(
        h,
        "c1",
        "upload_part",
        map(&[
            ("upload", id.clone().into()),
            ("index", Value::UInt(5)),
            ("data", Value::Bytes(vec![0; 10])),
        ]),
    )
    .await;
    assert_eq!(status(&a), Status::InvalidParameter, "index out of range");
    ok(
        h,
        "c1",
        "upload_abort",
        map(&[("upload", id.clone().into())]),
    )
    .await;
    let (a, _) = act(h, "c1", "upload_status", map(&[("upload", id.into())])).await;
    assert_eq!(status(&a), Status::NotFound);
    assert!(child(h, &reports, "x.bin").await.is_none());
}
