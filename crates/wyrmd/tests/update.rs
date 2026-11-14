//! The broker's own update end to end (ADR 0048 §2): two real `wyrmd`
//! binaries of different versions (the one of this build and
//! `wyrmd_next`), the install layout, the guard, and this test in
//! the place of the supervisor (`ExecStartPre` the guard, `ExecStart`
//! `<prefix>/current/wyrmd`, `Restart=always`).
#![cfg(unix)]

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_admin::release::{
    self, testkit, Asset, Identity, IndexEntry, IndexFile, Release, UpdateFile,
};
use wyrm_client::{SigningTokens, WyrmClient};
use wyrm_core::Value;

/// The admin key of the brokers here.
const SEED: [u8; 32] = [9; 32];
/// The release key the brokers pin (`updates.keys`).
const RELEASE_SEED: [u8; 32] = [7; 32];
const SITE: &str = "upd";

/// One broker update at a time: each test runs brokers of 350 MiB binaries.
static HEAVY: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// A loopback port below the ephemeral ranges, never handed out twice (the
/// scheme of `tests/e2e.rs`, with its lock files, so both can run at once).
fn free_port() -> u16 {
    use std::sync::atomic::AtomicU32;
    const FIRST: u32 = 20_000;
    const COUNT: u32 = 12_000;
    static NEXT: AtomicU32 = AtomicU32::new(0);
    static LOCKS: Mutex<Vec<std::fs::File>> = Mutex::new(Vec::new());
    let dir = std::env::temp_dir().join("wyrmd-e2e-ports");
    std::fs::create_dir_all(&dir).unwrap();
    let start = std::process::id().wrapping_mul(7_919) % COUNT;
    for _ in 0..COUNT {
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        let port = (FIRST + (start + n) % COUNT) as u16;
        let Ok(lock) = std::fs::File::create(dir.join(port.to_string())) else {
            continue;
        };
        if lock.try_lock().is_err() {
            continue;
        }
        let free = std::net::TcpListener::bind(("127.0.0.1", port)).is_ok()
            && std::net::UdpSocket::bind(("127.0.0.1", port)).is_ok();
        if free {
            LOCKS.lock().unwrap().push(lock);
            return port;
        }
    }
    panic!("no free port");
}

fn temp_dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrmd-update-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    // the layout is found by real paths (macOS: /var is a link)
    d.canonicalize().unwrap()
}

/// A binary cargo built for this test, small enough for an update. A debug
/// build on Linux keeps its debug info inside the executable and is then
/// larger than the largest binary an update takes (`MAX_BINARY`); such a
/// build is used as a copy without the debug info. A release is far below
/// the bound, so nothing but a test build needs this.
fn slim(built: &str, name: &str) -> PathBuf {
    let built = PathBuf::from(built);
    let size = std::fs::metadata(&built)
        .unwrap_or_else(|e| panic!("{}: {e}", built.display()))
        .len();
    if size <= release::MAX_BINARY / 2 {
        return built;
    }
    let copy = temp_dir("bins").join(name);
    let done = Command::new("strip")
        .arg("--strip-debug")
        .arg("-o")
        .arg(&copy)
        .arg(&built)
        .output()
        .unwrap_or_else(|e| {
            panic!(
                "{} has {size} bytes, more than an update takes, and `strip` cannot be run to \
                 drop its debug info: {e}",
                built.display()
            )
        });
    assert!(done.status.success(), "strip {}: {done:?}", built.display());
    let left = std::fs::metadata(&copy).unwrap().len();
    assert!(
        left <= release::MAX_BINARY,
        "{}: {left} bytes without the debug info, still more than an update takes",
        built.display()
    );
    copy
}

/// The broker of this build.
fn this_bin() -> PathBuf {
    static BIN: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
    BIN.get_or_init(|| slim(env!("CARGO_BIN_EXE_wyrmd"), "wyrmd"))
        .clone()
}

/// The second binary (`src/bin/wyrmd_next.rs`), built by cargo for this
/// test like `wyrmd` itself.
fn next_bin() -> PathBuf {
    static BIN: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
    BIN.get_or_init(|| slim(env!("CARGO_BIN_EXE_wyrmd_next"), "wyrmd_next"))
        .clone()
}

async fn eventually<T, F, Fut>(what: &str, secs: u64, mut f: F) -> T
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Option<T>>,
{
    let deadline = tokio::time::Instant::now() + Duration::from_secs(secs);
    loop {
        if let Some(v) = f().await {
            return v;
        }
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(200)).await;
    }
}

/// A client with the admin's tokens on a broker's loopback port, or `None`
/// while nothing listens there.
async fn client_on(port: u16) -> Option<WyrmClient> {
    let mut zc = zenoh::Config::default();
    zc.insert_json5("mode", r#""client""#).unwrap();
    zc.insert_json5("connect/endpoints", &format!(r#"["tcp/127.0.0.1:{port}"]"#))
        .unwrap();
    zc.insert_json5("connect/timeout_ms", "2000").unwrap();
    zc.insert_json5("scouting/multicast/enabled", "false")
        .unwrap();
    let session = zenoh::open(zc).await.ok()?;
    let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
    Some(
        WyrmClient::new(session)
            .with_tokens(Arc::new(SigningTokens::new(key, SITE)))
            .with_timeout(Duration::from_secs(60)),
    )
}

/// The value of `wy/<site>/sys/<leaf>` on the broker at `port`, through a
/// session of its own (the broker restarts under the test).
async fn sys(port: u16, leaf: &str) -> Option<Value> {
    let c = client_on(port).await?;
    let r = c
        .session()
        .get(format!("wy/{SITE}/sys/{leaf}/~val"))
        .timeout(Duration::from_secs(3))
        .await
        .ok()?;
    let reply = r.recv_async().await.ok()?;
    let s = reply.result().ok()?;
    wyrm_core::codec::from_slice::<wyrm_core::Sample>(&s.payload().to_bytes())
        .ok()
        .map(|s| s.v)
}

async fn sys_str(port: u16, leaf: &str) -> Option<String> {
    match sys(port, leaf).await? {
        Value::Str(s) => Some(s),
        _ => None,
    }
}

fn args(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// The operations of the last audit records.
async fn audit_ops(port: u16) -> Vec<(String, String)> {
    let c = client_on(port).await.expect("a session");
    let Some(Value::Array(rows)) = c
        .invoke_one(
            &format!("wy/{SITE}/sys/audit"),
            "tail",
            args(&[("n", Value::UInt(500))]),
        )
        .await
        .unwrap()
    else {
        panic!("audit tail: an array");
    };
    rows.into_iter()
        .filter_map(|r| match r {
            Value::Map(m) => match (m.get("op"), m.get("detail")) {
                (Some(Value::Str(op)), Some(Value::Str(d))) => Some((op.clone(), d.clone())),
                _ => None,
            },
            _ => None,
        })
        .collect()
}

/// This test in the place of systemd: the guard before every start, then
/// `<prefix>/current/wyrmd`, started again whenever it ends. Both get an
/// empty environment.
struct Unit {
    stop: Arc<AtomicBool>,
    /// Exit codes of the broker, in order.
    exits: Arc<Mutex<Vec<i32>>>,
    /// Times the guard ended with an error: the broker was not started.
    refused: Arc<std::sync::atomic::AtomicU32>,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl Unit {
    fn start(prefix: &Path, cfg: &Path) -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        let exits = Arc::new(Mutex::new(Vec::new()));
        let refused = Arc::new(std::sync::atomic::AtomicU32::new(0));
        let (stop2, exits2, refused2) = (stop.clone(), exits.clone(), refused.clone());
        let (prefix, cfg) = (prefix.to_owned(), cfg.to_owned());
        let thread = std::thread::spawn(move || {
            while !stop2.load(Ordering::SeqCst) {
                let guard = Command::new(prefix.join("bin").join(release::GUARD))
                    .arg("-c")
                    .arg(&cfg)
                    .arg("update-guard")
                    .env_clear()
                    .stdout(Stdio::null())
                    .stderr(Stdio::inherit())
                    .status();
                if !guard.is_ok_and(|s| s.success()) {
                    // ExecStartPre failed: the broker is not started
                    refused2.fetch_add(1, Ordering::SeqCst);
                    std::thread::sleep(Duration::from_millis(500));
                    continue;
                }
                let mut broker = Command::new(prefix.join("current").join(release::BIN))
                    .arg("-c")
                    .arg(&cfg)
                    .env_clear()
                    .env("RUST_LOG", "warn")
                    .stdout(Stdio::null())
                    .stderr(Stdio::inherit())
                    .spawn()
                    .expect("spawn wyrmd");
                loop {
                    if stop2.load(Ordering::SeqCst) {
                        let _ = broker.kill();
                        let _ = broker.wait();
                        return;
                    }
                    match broker.try_wait() {
                        Ok(Some(status)) => {
                            exits2.lock().unwrap().push(status.code().unwrap_or(-1));
                            break;
                        }
                        Ok(None) => std::thread::sleep(Duration::from_millis(50)),
                        Err(_) => return,
                    }
                }
                // RestartSec
                std::thread::sleep(Duration::from_millis(500));
            }
        });
        Self {
            stop,
            exits,
            refused,
            thread: Some(thread),
        }
    }

    fn exits(&self) -> Vec<i32> {
        self.exits.lock().unwrap().clone()
    }
}

impl Unit {
    fn stop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

impl Drop for Unit {
    fn drop(&mut self) {
        self.stop();
    }
}

/// A site in the install layout, on the `wyrmd` of this build (0.1.0 of
/// the workspace), with an embedded and a process link.
struct Site {
    cfg: PathBuf,
    root: PathBuf,
    prefix: PathBuf,
    data: PathBuf,
    port: u16,
    unit: Unit,
}

fn release_key() -> ed25519_dalek::SigningKey {
    ed25519_dalek::SigningKey::from_bytes(&RELEASE_SEED)
}

/// An embedded and a process link.
const LINKS: &str = r#"links: {
    mock: { driver: "mock", params: { points: 4, rate_hz: 2, depth: 1, fanout: 2 } },
    mockp: { driver: "mock", mode: "process", params: { points: 4, rate_hz: 2, depth: 1, fanout: 2 } },
},"#;

impl Site {
    /// A site with the two links, serving.
    async fn start(name: &str, updates: &str) -> Self {
        let site = Self::launch(name, updates, LINKS, |_| {});
        site.wait_version("0.1.0").await;
        site.wait_links().await;
        site
    }

    /// The layout, the configuration (`updates`: more fields of that
    /// section; `extra`: more top-level fields) and the unit; `before` runs
    /// on the data directory before the first start.
    fn launch(name: &str, updates: &str, extra: &str, before: impl FnOnce(&Path)) -> Self {
        let root = temp_dir(name);
        let (prefix, data) = (root.join("opt"), root.join("data"));
        let made = Command::new(this_bin())
            .arg("install-layout")
            .arg(&prefix)
            .env_clear()
            .output()
            .unwrap();
        assert!(made.status.success(), "install-layout: {made:?}");
        let said = String::from_utf8_lossy(&made.stdout);
        assert!(
            said.contains("ExecStartPre=") && said.contains("update-guard"),
            "{said}"
        );
        let (port, tls) = (free_port(), free_port());
        let admin = hex::encode(
            ed25519_dalek::SigningKey::from_bytes(&SEED)
                .verifying_key()
                .to_bytes(),
        );
        let pinned = hex::encode(release_key().verifying_key().to_bytes());
        let cfg = root.join("wyrmd.json5");
        std::fs::write(
            &cfg,
            format!(
                r#"{{
                    site: "{SITE}",
                    data_dir: "{}",
                    listen: ["tcp/127.0.0.1:{port}", "tls/127.0.0.1:{tls}"],
                    admin_keys: ["{admin}"],
                    metrics_interval_ms: 200,
                    updates: {{ mode: "self", keys: ["{pinned}"], trial_s: 25, {updates} }},
                    {extra}
                    /*more*/
                }}"#,
                data.display()
            ),
        )
        .unwrap();
        before(&data);
        let unit = Unit::start(&prefix, &cfg);
        Self {
            cfg,
            root,
            prefix,
            data,
            port,
            unit,
        }
    }

    /// Stop the broker, add `more` top-level fields to its configuration
    /// and start it again.
    fn restart_with(&mut self, more: &str) {
        self.unit.stop();
        let text = std::fs::read_to_string(&self.cfg).unwrap();
        std::fs::write(&self.cfg, text.replace("/*more*/", more)).unwrap();
        self.unit = Unit::start(&self.prefix, &self.cfg);
    }

    async fn wait_version(&self, v: &str) {
        let port = self.port;
        eventually(&format!("wyrmd {v} serves"), 240, || async move {
            (sys_str(port, "version").await.as_deref() == Some(v)).then_some(())
        })
        .await;
    }

    /// Both links connected (state 2).
    async fn wait_links(&self) {
        let port = self.port;
        eventually("both links connected", 120, || async move {
            for l in ["mock", "mockp"] {
                if sys(port, &format!("links/{l}/state")).await != Some(Value::UInt(2)) {
                    return None;
                }
            }
            Some(())
        })
        .await;
    }

    async fn wait_state(&self, state: &str) {
        let port = self.port;
        eventually(&format!("update_state {state}"), 240, || async move {
            (sys_str(port, "update_state").await.as_deref() == Some(state)).then_some(())
        })
        .await;
    }

    async fn client(&self) -> WyrmClient {
        let port = self.port;
        eventually("a session", 60, || client_on(port)).await
    }

    fn sys_node(&self) -> String {
        format!("wy/{SITE}/sys")
    }

    fn current(&self) -> String {
        std::fs::read_link(self.prefix.join("current"))
            .unwrap()
            .to_string_lossy()
            .into_owned()
    }

    fn update_file(&self) -> UpdateFile {
        UpdateFile::load(&self.data).expect("update.json")
    }
}

/// What the second binary says it is, as `release-info` prints it.
fn next_identity() -> Identity {
    let out = Command::new(next_bin())
        .arg("release-info")
        .env_clear()
        .output()
        .unwrap();
    assert!(out.status.success(), "{out:?}");
    serde_json::from_slice(&out.stdout).unwrap()
}

fn release_of(id: &Identity, asset: Asset) -> Release {
    Release {
        wyrmd_release: release::FORMAT,
        version: id.version.clone(),
        date: "2026-11-13".into(),
        notes: String::new(),
        min_from: String::new(),
        schemas: id.schemas.clone(),
        replication: id.replication,
        targets: BTreeMap::from([(id.target.clone(), asset)]),
    }
}

/// A loopback HTTP server for a releases index and its archives.
type Files = BTreeMap<String, Arc<Vec<u8>>>;

fn serve(files: Files) -> u16 {
    serve_shared(Arc::new(Mutex::new(files)))
}

/// [`serve`] with files that the test replaces while it runs.
fn serve_shared(files: Arc<Mutex<Files>>) -> u16 {
    use std::io::{Read, Write};
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut s) = stream else { continue };
            let files = files.lock().unwrap().clone();
            std::thread::spawn(move || {
                let mut req = Vec::new();
                let mut buf = [0u8; 1024];
                while !req.windows(4).any(|w| w == b"\r\n\r\n") {
                    match s.read(&mut buf) {
                        Ok(0) | Err(_) => return,
                        Ok(n) => req.extend_from_slice(&buf[..n]),
                    }
                }
                let text = String::from_utf8_lossy(&req).into_owned();
                let path = text.split_whitespace().nth(1).unwrap_or("/").to_owned();
                match files.get(&path) {
                    Some(body) => {
                        let head = format!(
                            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                            body.len()
                        );
                        let _ = s.write_all(head.as_bytes());
                        let _ = s.write_all(body);
                    }
                    None => {
                        let _ = s.write_all(
                            b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                        );
                    }
                }
            });
        }
    });
    port
}

/// The bytes of an index of `releases` with `sequence`, every entry signed
/// by `signer`.
fn index_bytes(releases: &[Release], signer: &ed25519_dalek::SigningKey, sequence: u64) -> Vec<u8> {
    let file = IndexFile {
        wyrmd_releases: release::FORMAT,
        sequence,
        created: "2026-11-13".into(),
        releases: releases
            .iter()
            .map(|r| {
                let doc = serde_json::to_string(r).unwrap();
                IndexEntry {
                    signature: release::sign_release(doc.as_bytes(), signer),
                    release: doc,
                }
            })
            .collect(),
    };
    serde_json::to_vec(&file).unwrap()
}

/// The channel file of `index` signed by `signer`, as the files of a channel.
fn channel_of(index: &[u8], signer: &ed25519_dalek::SigningKey) -> Files {
    let sig = release::sign_index(index, signer);
    BTreeMap::from([(
        "/releases.json".to_owned(),
        Arc::new(release::bundle(index, &sig).unwrap()),
    )])
}

/// A signed index (sequence 7) of `releases` as the files of a channel.
fn channel_files(releases: Vec<Release>) -> Files {
    channel_of(&index_bytes(&releases, &release_key(), 7), &release_key())
}

/// Bring `bytes` to the broker in parts (the upload of the backups).
async fn upload_parts(c: WyrmClient, bytes: Vec<u8>) -> String {
    let backups = format!("wy/{SITE}/sys/backups");
    let begin = args(&[("size", Value::UInt(bytes.len() as u64))]);
    let Some(Value::Map(m)) = c
        .invoke_one(&backups, "restore_begin", begin)
        .await
        .unwrap()
    else {
        panic!("restore_begin: a map");
    };
    let Some(Value::Str(id)) = m.get("upload").cloned() else {
        panic!("restore_begin: upload");
    };
    let mut offset = 0u64;
    for chunk in bytes.chunks(8 << 20) {
        let part = args(&[
            ("upload", id.clone().into()),
            ("offset", Value::UInt(offset)),
            ("data", Value::Bytes(chunk.to_vec())),
        ]);
        c.invoke_one(&backups, "restore_part", part).await.unwrap();
        offset += chunk.len() as u64;
    }
    id
}

/// A good update from the releases index: the new version is fetched,
/// checked, started, proven for its trial and confirmed; then it is rolled
/// back on purpose.
#[tokio::test(flavor = "multi_thread")]
async fn a_broker_updates_itself_and_is_confirmed() {
    let _heavy = HEAVY.lock().await;
    let id = next_identity();
    assert_eq!(id.version, "0.2.0");
    assert_ne!(
        release::sha256_file(&next_bin()).unwrap(),
        release::sha256_file(&this_bin()).unwrap(),
        "two different binaries"
    );
    // the channel: an index and the archive beside it
    let stage = temp_dir("good-channel");
    let file = format!("wyrmd-0.2.0-{}.tar.gz", id.target);
    let asset = testkit::archive_of(&next_bin(), &[], &stage.join(&file)).unwrap();
    let mut files = channel_files(vec![release_of(&id, asset)]);
    files.insert(
        format!("/{file}"),
        Arc::new(std::fs::read(stage.join(&file)).unwrap()),
    );
    let http = serve(files);
    let mut site = Site::start(
        "good",
        &format!(r#"channel: "http://127.0.0.1:{http}/releases.json""#),
    )
    .await;
    let c = site.client().await;
    let node = site.sys_node();

    // the broker reads the index and says what it found
    let found = c
        .invoke_one(&node, "check_updates", args(&[]))
        .await
        .unwrap();
    let Some(Value::Map(found)) = found else {
        panic!("check_updates: a map");
    };
    assert_eq!(found.get("latest"), Some(&Value::from("0.2.0")));
    assert_eq!(found.get("update_available"), Some(&Value::Bool(true)));
    assert_eq!(
        sys_str(site.port, "update_mode").await.as_deref(),
        Some("self")
    );
    assert_eq!(
        sys_str(site.port, "update_state").await.as_deref(),
        Some("none")
    );
    assert_eq!(
        sys_str(site.port, "update_hint").await.as_deref(),
        Some(""),
        "the layout and the guard are in place"
    );

    // the site name confirms; a dry run refuses the same way and does nothing
    let wrong = args(&[("confirm_site", "other".into())]);
    let e = c
        .invoke_check(&node, "update", wrong.clone())
        .await
        .unwrap_err();
    assert!(e.message.contains("confirm_site"), "{}", e.message);
    let e = c.invoke_one(&node, "update", wrong).await.unwrap_err();
    assert!(e.message.contains("confirm_site"), "{}", e.message);
    let go = args(&[("confirm_site", SITE.into())]);
    c.invoke_check(&node, "update", go.clone()).await.unwrap();
    assert_eq!(
        site.current(),
        "versions/0.1.0",
        "a dry run changes nothing"
    );

    let Some(Value::Map(answer)) = c.invoke_one(&node, "update", go.clone()).await.unwrap() else {
        panic!("update: a map");
    };
    assert_eq!(answer.get("success"), Some(&Value::Bool(true)));
    assert_eq!(answer.get("version"), Some(&Value::from("0.2.0")));
    // a second one while the first is prepared
    let e = c.invoke_one(&node, "update", go).await.unwrap_err();
    assert!(e.is(wyrm_core::Status::Busy), "{}", e.message);
    drop(c);

    // the new version serves, in its trial first
    site.wait_version("0.2.0").await;
    assert_eq!(site.current(), "versions/0.2.0");
    let u = site.update_file();
    assert_eq!((u.from.as_str(), u.to.as_str()), ("0.1.0", "0.2.0"));
    assert_eq!(u.links, ["mock", "mockp"], "the links that must come back");
    assert!(u.moved().is_empty());
    assert!(
        u.attempts >= 1,
        "the guard counted the start of the new version"
    );
    assert!(
        u.deadline > u.started,
        "the trial began when the new version started"
    );
    // the guard is still the old version while the trial runs
    if u.in_trial() {
        assert_eq!(
            release::sha256_file(&site.prefix.join("bin").join(release::GUARD)).unwrap(),
            release::sha256_file(&this_bin()).unwrap()
        );
    }
    site.wait_state("confirmed").await;
    site.wait_links().await;
    let u = site.update_file();
    assert_eq!(u.state, "confirmed");
    assert!(
        u.ran_s >= u.trial_s && u.trial_s == 25,
        "confirmed only after the version ran its trial: ran {} of {} s",
        u.ran_s,
        u.trial_s
    );
    assert!(u.settled || u.starts == 0);
    assert!(u.keep_until > u.ended && u.without_s >= 1);
    // the guard follows the confirmed version
    assert_eq!(
        release::sha256_file(&site.prefix.join("bin").join(release::GUARD)).unwrap(),
        release::sha256_file(&next_bin()).unwrap()
    );
    assert_eq!(
        site.unit.exits(),
        [0],
        "the old version stopped cleanly, once"
    );
    // the pre-update backup is kept and pinned while a rollback is possible
    let job: serde_json::Value = serde_json::from_slice(
        &std::fs::read(site.data.join("backups").join(format!("{}.json", u.backup))).unwrap(),
    )
    .unwrap();
    assert_eq!(job["kind"], "pre-update");
    assert_eq!(job["pinned"], true);
    assert_eq!(job["sha256"], u.backup_sha256.as_str());
    let ops = audit_ops(site.port).await;
    let has = |op: &str| ops.iter().any(|(o, _)| o == op);
    assert!(has("update_start") && has("update_confirmed"), "{ops:?}");
    let Some(Value::Map(last)) = sys(site.port, "update_last").await else {
        panic!("update_last: a map");
    };
    assert_eq!(last.get("result"), Some(&Value::from("confirmed")));
    assert_eq!(last.get("from"), Some(&Value::from("0.1.0")));

    // on purpose, back to 0.1.0: the guard (now 0.2.0) does it at the next start
    let c = site.client().await;
    let e = c
        .invoke_one(
            &node,
            "rollback_update",
            args(&[("confirm_site", "x".into())]),
        )
        .await
        .unwrap_err();
    assert!(e.message.contains("confirm_site"), "{}", e.message);
    c.invoke_one(
        &node,
        "rollback_update",
        args(&[("confirm_site", SITE.into())]),
    )
    .await
    .unwrap();
    drop(c);
    site.wait_version("0.1.0").await;
    site.wait_state("rolled_back").await;
    assert_eq!(site.current(), "versions/0.1.0");
    let u = site.update_file();
    assert!(u.reason.contains("rolled back by"), "{}", u.reason);
    assert!(!u.restored, "no SCHEMA moved: nothing is restored");
    let ops = audit_ops(site.port).await;
    assert!(ops.iter().any(|(o, _)| o == "update_rollback"), "{ops:?}");
    assert_eq!(site.unit.exits(), [0, 0]);

    // the binary of the version that is current is replaced on disk (by
    // one that the release key did sign, for another version): the guard
    // does not let it start, and nothing else is there to start
    let port = site.port;
    let gone = site.prefix.join("versions").join("0.2.0");
    eventually("the version that was rolled back is removed", 60, || {
        let gone = gone.clone();
        async move { (!gone.exists()).then_some(()) }
    })
    .await;
    site.unit.stop();
    let bin = site
        .prefix
        .join("versions")
        .join("0.1.0")
        .join(release::BIN);
    let real = site.root.join("wyrmd.real");
    std::fs::rename(&bin, &real).unwrap();
    std::fs::copy(next_bin(), &bin).unwrap();
    site.unit = Unit::start(&site.prefix, &site.cfg);
    let refused = site.unit.refused.clone();
    eventually("the guard refuses the start", 60, || {
        let refused = refused.clone();
        async move { (refused.load(Ordering::SeqCst) >= 3).then_some(()) }
    })
    .await;
    assert!(
        site.unit.exits().is_empty(),
        "the replaced binary was never run: {:?}",
        site.unit.exits()
    );
    assert!(client_on(port).await.is_none(), "no broker is up");
    // the real binary back: it starts
    site.unit.stop();
    std::fs::rename(&real, &bin).unwrap();
    site.unit = Unit::start(&site.prefix, &site.cfg);
    site.wait_version("0.1.0").await;
    assert_eq!(site.unit.refused.load(Ordering::SeqCst), 0);
    let root = site.root.clone();
    drop(site);
    let _ = std::fs::remove_dir_all(root);
    let _ = std::fs::remove_dir_all(stage);
}

/// An update whose trial fails: a signed archive brought in parts, a new
/// version that says it moves the registry SCHEMA, a link that does not
/// come back. The new version gives up with code 76, the guard puts
/// `current` back and restores the control plane from the pre-update
/// backup, and the old version serves again with what it had.
#[tokio::test(flavor = "multi_thread")]
async fn a_failed_trial_is_rolled_back_by_the_guard() {
    let _heavy = HEAVY.lock().await;
    let mut id = next_identity();
    id.version = "0.3.0".into();
    *id.schemas.get_mut("registry").unwrap() += 1;
    let stage = temp_dir("bad-archive");
    let file = format!("wyrmd-0.3.0-{}.tar.gz", id.target);
    // the same binary with a note beside it: it says it is 0.3.0 and
    // writes a later registry SCHEMA
    let note = br#"{"version": "0.3.0", "schema_bump": {"registry": 1}}"#;
    let asset = testkit::archive_of(
        &next_bin(),
        &[("test-build.json", note)],
        &stage.join(&file),
    )
    .unwrap();
    let rel = release_of(&id, asset);
    let doc = serde_json::to_vec(&rel).unwrap();
    let signature = release::sign_release(&doc, &release_key());

    let site = Site::start("bad", "").await;
    let c = site.client().await;
    let node = site.sys_node();
    let with = |doc: &[u8], signature: &str, upload: &str| {
        args(&[
            ("confirm_site", SITE.into()),
            ("upload", upload.into()),
            (
                "release",
                Value::Str(String::from_utf8_lossy(doc).into_owned()),
            ),
            ("signature", signature.into()),
        ])
    };
    // a release that another key signed, and one that is changed after it
    // was signed: refused before the archive is looked at
    let other = ed25519_dalek::SigningKey::from_bytes(&[3; 32]);
    let forged = release::sign_release(&doc, &other);
    let e = c
        .invoke_one(&node, "update", with(&doc, &forged, "none"))
        .await
        .unwrap_err();
    assert!(e.message.contains("pinned release key"), "{}", e.message);
    let mut changed = rel.clone();
    changed.targets.values_mut().next().unwrap().sha256 = "0".repeat(64);
    let e = c
        .invoke_one(
            &node,
            "update",
            with(&serde_json::to_vec(&changed).unwrap(), &signature, "none"),
        )
        .await
        .unwrap_err();
    assert!(e.message.contains("pinned release key"), "{}", e.message);
    // a signed release of an older version: never down
    let mut older = rel.clone();
    older.version = "0.0.9".into();
    let older = serde_json::to_vec(&older).unwrap();
    let e = c
        .invoke_one(
            &node,
            "update",
            with(
                &older,
                &release::sign_release(&older, &release_key()),
                "none",
            ),
        )
        .await
        .unwrap_err();
    assert!(e.message.contains("never goes down"), "{}", e.message);
    // a signed release, an archive that is not its archive
    let upload = |bytes: Vec<u8>| upload_parts(c.clone(), bytes);
    let junk = upload(b"not the archive".to_vec()).await;
    c.invoke_one(&node, "update", with(&doc, &signature, &junk))
        .await
        .unwrap();
    let port = site.port;
    let reason = eventually("the wrong archive is refused", 120, || async move {
        match sys(port, "update_last").await? {
            Value::Map(m) => match (m.get("result"), m.get("reason")) {
                (Some(Value::Str(r)), Some(Value::Str(why))) if r == "failed" => Some(why.clone()),
                _ => None,
            },
            _ => None,
        }
    })
    .await;
    assert!(
        reason.contains("bytes") || reason.contains("SHA-256"),
        "{reason}"
    );
    assert_eq!(site.current(), "versions/0.1.0");
    assert!(!site.prefix.join("versions").join("0.3.0").exists());
    assert!(UpdateFile::load(&site.data).is_none());

    // what the old version has before the update
    let all_links = format!("{node}/allow_all_links");
    assert_eq!(
        sys(site.port, "allow_all_links").await,
        Some(Value::Bool(false))
    );

    // the real archive, in parts
    let id_up = upload(std::fs::read(stage.join(&file)).unwrap()).await;
    c.invoke_one(&node, "update", with(&doc, &signature, &id_up))
        .await
        .unwrap();
    drop(c);
    site.wait_version("0.3.0").await;
    assert_eq!(site.current(), "versions/0.3.0");
    let u = site.update_file();
    assert_eq!(u.moved(), ["registry"]);
    assert_eq!(u.state, "trial");

    // under the new version: the control plane moves, and a link goes away
    let c = site.client().await;
    c.set(&all_links, true).await.unwrap();
    c.invoke_one(&format!("{node}/links/mockp"), "stop", args(&[]))
        .await
        .unwrap();
    drop(c);
    assert_eq!(
        sys(site.port, "allow_all_links").await,
        Some(Value::Bool(true))
    );

    // the trial ends without the link: 76, the guard, the old version
    site.wait_version("0.1.0").await;
    site.wait_state("rolled_back").await;
    assert_eq!(site.current(), "versions/0.1.0");
    assert!(
        site.unit.exits().contains(&release::TRIAL_EXIT),
        "the new version ended with 76: {:?}",
        site.unit.exits()
    );
    let u = site.update_file();
    assert_eq!(u.state, "rolled_back");
    assert!(
        u.restored,
        "the registry is restored from the pre-update backup"
    );
    assert!(u.reason.contains("mockp"), "{}", u.reason);
    // the control plane is the one of before the update
    assert_eq!(
        sys(site.port, "allow_all_links").await,
        Some(Value::Bool(false))
    );
    site.wait_links().await;
    let ops = audit_ops(site.port).await;
    let rolled = ops
        .iter()
        .find(|(o, _)| o == "update_rollback")
        .unwrap_or_else(|| panic!("no update_rollback in {ops:?}"));
    assert!(
        rolled.1.contains("control plane restored: true"),
        "{rolled:?}"
    );
    assert!(ops.iter().any(|(o, _)| o == "update_start"), "{ops:?}");
    let Some(Value::Map(last)) = sys(site.port, "update_last").await else {
        panic!("update_last: a map");
    };
    assert_eq!(last.get("result"), Some(&Value::from("rolled_back")));
    assert_eq!(last.get("restored"), Some(&Value::Bool(true)));
    // the version that failed is removed; what it wrote is kept aside
    let port = site.port;
    let gone = site.prefix.join("versions").join("0.3.0");
    eventually("the failed version is removed", 30, || {
        let gone = gone.clone();
        async move {
            let _ = port;
            (!gone.exists()).then_some(())
        }
    })
    .await;
    assert!(site.data.join("update.aside").join("state").is_dir());
    let root = site.root.clone();
    drop(site);
    let _ = std::fs::remove_dir_all(root);
    let _ = std::fs::remove_dir_all(stage);
}

/// A standby pair (ADR 0036): the standby is updated first, on the
/// active's order, and proven; only then the active updates.
#[tokio::test(flavor = "multi_thread")]
async fn a_standby_is_updated_before_the_active() {
    let _heavy = HEAVY.lock().await;
    let id = next_identity();
    let stage = temp_dir("pair-archive");
    let file = format!("wyrmd-0.2.0-{}.tar.gz", id.target);
    let asset = testkit::archive_of(&next_bin(), &[], &stage.join(&file)).unwrap();
    let doc = serde_json::to_vec(&release_of(&id, asset)).unwrap();
    let signature = release::sign_release(&doc, &release_key());
    let archive = std::fs::read(stage.join(&file)).unwrap();

    // a witness both hosts reach
    let witness = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let wport = witness.local_addr().unwrap().port();
    std::thread::spawn(move || for _ in witness.incoming() {});
    let (a_quic, b_quic) = (free_port(), free_port());
    let peers = |own: u16| format!(r#"peers: {{ listen: "quic/127.0.0.1:{own}" }},"#);
    let standby = |peer: u16, primary: bool| {
        format!(
            r#"standby: {{ peer: "quic/127.0.0.1:{peer}", takeover_s: 3, primary: {primary},
                          witness: ["127.0.0.1:{wport}"] }},"#
        )
    };
    // the active: a broker that has run (it has the site's keys), then one
    // of a pair; it starts alone and takes the role
    let mut a = Site::launch("pair-a", "", &peers(a_quic), |_| {});
    a.wait_version("0.1.0").await;
    a.restart_with(&standby(b_quic, true));
    let port = a.port;
    eventually("the active is one of a pair", 120, || async move {
        sys(port, "standby_version").await.map(|_| ())
    })
    .await;
    // the standby: the site's keys, then it follows
    const PASS: &[u8] = b"a passphrase for the pair";
    let bundle = wyrm_admin::keys::export(&a.data, PASS).unwrap();
    let pair_b = format!("{} {}", peers(b_quic), standby(a_quic, false));
    let b = Site::launch("pair-b", "", &pair_b, |data| {
        std::fs::create_dir_all(data).unwrap();
        wyrm_admin::keys::import(data, &bundle, PASS).unwrap();
    });
    eventually(
        "the standby follows and says what it runs",
        120,
        || async move {
            (sys_str(port, "standby_version").await.as_deref() == Some("0.1.0")).then_some(())
        },
    )
    .await;

    let c = a.client().await;
    let node = a.sys_node();
    let with = |upload: &str, target: Option<&str>| {
        let mut v = vec![
            ("confirm_site", Value::from(SITE)),
            ("upload", upload.into()),
            (
                "release",
                Value::Str(String::from_utf8_lossy(&doc).into_owned()),
            ),
            ("signature", signature.as_str().into()),
        ];
        if let Some(t) = target {
            v.push(("target", t.into()));
        }
        args(&v)
    };
    // the active does not go first
    let e = c
        .invoke_one(&node, "update", with("none", None))
        .await
        .unwrap_err();
    assert!(e.is(wyrm_core::Status::Busy), "{}", e.message);
    assert!(
        e.message.contains("update the standby first"),
        "{}",
        e.message
    );
    assert_eq!(a.current(), "versions/0.1.0");

    // the order for the standby
    let up = upload_parts(c.clone(), archive.clone()).await;
    c.invoke_one(&node, "update", with(&up, Some("standby")))
        .await
        .unwrap();
    eventually("the standby runs 0.2.0, proven", 300, || async move {
        (sys_str(port, "standby_update").await.as_deref() == Some("0.2.0 confirmed")
            && sys_str(port, "standby_version").await.as_deref() == Some("0.2.0"))
        .then_some(())
    })
    .await;
    assert_eq!(b.current(), "versions/0.2.0");
    assert_eq!(
        a.current(),
        "versions/0.1.0",
        "the active still runs the old version"
    );
    let u = b.update_file();
    assert_eq!(
        (u.state.as_str(), u.role.as_str()),
        ("confirmed", "standby")
    );
    assert_eq!(
        b.unit.exits(),
        [0],
        "the standby stopped once, for its update"
    );
    assert!(a.unit.exits().is_empty(), "the active did not stop for it");
    let ops = audit_ops(a.port).await;
    assert!(
        ops.iter()
            .any(|(o, d)| o == "update_confirmed" && d.contains("the standby runs 0.2.0")),
        "{ops:?}"
    );

    // now the active; the standby waits and does not take over
    let up = upload_parts(c.clone(), archive).await;
    c.invoke_one(&node, "update", with(&up, None))
        .await
        .unwrap();
    drop(c);
    a.wait_version("0.2.0").await;
    a.wait_state("confirmed").await;
    assert_eq!(a.current(), "versions/0.2.0");
    assert_eq!(a.unit.exits(), [0]);
    assert_eq!(b.unit.exits(), [0], "the standby kept following");
    eventually("the standby follows the new active", 120, || async move {
        (sys_str(port, "standby_version").await.as_deref() == Some("0.2.0")).then_some(())
    })
    .await;
    let roots = [a.root.clone(), b.root.clone(), stage];
    drop(b);
    drop(a);
    for r in roots {
        let _ = std::fs::remove_dir_all(r);
    }
}

/// A daemon in this process, stopped when dropped.
struct Local {
    port: u16,
    stop: Option<tokio::sync::oneshot::Sender<()>>,
    task: Option<tokio::task::JoinHandle<Result<(), wyrmd::Error>>>,
    dir: PathBuf,
}

impl Local {
    async fn start(name: &str, updates: &str) -> Self {
        let _ = wyrm_admin::logs::install_quiet();
        let dir = temp_dir(name);
        let port = free_port();
        let admin = hex::encode(
            ed25519_dalek::SigningKey::from_bytes(&SEED)
                .verifying_key()
                .to_bytes(),
        );
        let cfg = wyrmd::Config::from_json5(&format!(
            r#"{{ site: "{SITE}", data_dir: "{}", listen: ["tcp/127.0.0.1:{port}"],
                 admin_keys: ["{admin}"], {updates} }}"#,
            dir.join("data").display()
        ))
        .unwrap();
        let daemon = wyrmd::Daemon::open(cfg, this_bin()).unwrap();
        let (stop, rx) = tokio::sync::oneshot::channel();
        let task = tokio::spawn(daemon.run_until(async {
            let _ = rx.await;
        }));
        eventually("the broker listens", 60, || async move {
            sys_str(port, "version").await.map(|_| ())
        })
        .await;
        Self {
            port,
            stop: Some(stop),
            task: Some(task),
            dir,
        }
    }

    async fn stop(mut self) {
        let _ = self.stop.take().unwrap().send(());
        self.task.take().unwrap().await.unwrap().unwrap();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

/// `external` says that a newer version exists and what to run, and never
/// updates; `off` (the default) says nothing; `self` outside the install
/// layout is refused with the reason.
#[tokio::test(flavor = "multi_thread")]
async fn external_mode_reports_only() {
    let _heavy = HEAVY.lock().await;
    let me = wyrmd::update::identity(None);
    let newer = Identity {
        version: "0.9.0".into(),
        ..me.clone()
    };
    let asset = Asset {
        file: format!("wyrmd-0.9.0-{}.tar.gz", me.target),
        sha256: "a".repeat(64),
        size: 1000,
        url: String::new(),
        bin_sha256: "b".repeat(64),
    };
    let served = Arc::new(Mutex::new(channel_files(vec![release_of(
        &newer,
        asset.clone(),
    )])));
    let http = serve_shared(served.clone());
    let pinned = hex::encode(release_key().verifying_key().to_bytes());
    let node = format!("wy/{SITE}/sys");
    let go = args(&[("confirm_site", SITE.into())]);

    let ext = Local::start(
        "external",
        &format!(
            r#"updates: {{ mode: "external", keys: ["{pinned}"],
                 channel: "http://127.0.0.1:{http}/releases.json" }}"#
        ),
    )
    .await;
    let c = client_on(ext.port).await.unwrap();
    c.invoke_one(&node, "check_updates", args(&[]))
        .await
        .unwrap();
    let port = ext.port;
    eventually("the newer version is shown", 30, || async move {
        (sys(port, "update_available").await == Some(Value::Bool(true))).then_some(())
    })
    .await;
    assert_eq!(sys_str(ext.port, "latest").await.as_deref(), Some("0.9.0"));
    assert_eq!(
        sys_str(ext.port, "update_mode").await.as_deref(),
        Some("external")
    );
    assert_eq!(
        sys_str(ext.port, "update_state").await.as_deref(),
        Some("none")
    );
    let hint = sys_str(ext.port, "update_hint").await.unwrap();
    assert!(
        hint.contains("wyrmd 0.9.0") && hint.contains("docker compose pull"),
        "{hint}"
    );
    let e = c.invoke_one(&node, "update", go.clone()).await.unwrap_err();
    assert!(e.is(wyrm_core::Status::NotSupported), "{}", e.message);
    assert!(e.message.contains("updated outside"), "{}", e.message);
    let e = c
        .invoke_check(&node, "update", go.clone())
        .await
        .unwrap_err();
    assert!(e.message.contains("updated outside"), "{}", e.message);
    // an older index, validly signed, is put back (it hides 0.9.0): it is
    // refused, and what was read before stays
    let older = Identity {
        version: "0.5.0".into(),
        ..me.clone()
    };
    let old_index = index_bytes(&[release_of(&older, asset.clone())], &release_key(), 6);
    *served.lock().unwrap() = channel_of(&old_index, &release_key());
    let e = c
        .invoke_one(&node, "check_updates", args(&[]))
        .await
        .unwrap_err();
    assert!(
        e.message.contains("older than one this broker has read"),
        "{}",
        e.message
    );
    assert_eq!(sys_str(ext.port, "latest").await.as_deref(), Some("0.9.0"));
    // the same sequence again is taken
    *served.lock().unwrap() = channel_files(vec![release_of(&newer, asset.clone())]);
    c.invoke_one(&node, "check_updates", args(&[]))
        .await
        .unwrap();
    drop(c);
    ext.stop().await;

    // an index that another key signed
    let other = ed25519_dalek::SigningKey::from_bytes(&[3; 32]);
    let foreign = index_bytes(&[release_of(&newer, asset.clone())], &other, 7);
    let forged = serve(channel_of(&foreign, &other));
    // an index the pinned key signed as a whole, with an entry it did not
    // sign: the entry is not trusted because the list is
    let planted = serve(channel_of(&foreign, &release_key()));
    let ext = Local::start(
        "external-planted",
        &format!(
            r#"updates: {{ mode: "external", keys: ["{pinned}"],
                 channel: "http://127.0.0.1:{planted}/releases.json" }}"#
        ),
    )
    .await;
    let c = client_on(ext.port).await.unwrap();
    let e = c
        .invoke_one(&node, "check_updates", args(&[]))
        .await
        .unwrap_err();
    assert!(e.message.contains("an entry is refused"), "{}", e.message);
    assert_eq!(
        sys(ext.port, "update_available").await,
        Some(Value::Bool(false))
    );
    assert_eq!(sys_str(ext.port, "latest").await.as_deref(), Some(""));
    drop(c);
    ext.stop().await;
    let ext = Local::start(
        "external-forged",
        &format!(
            r#"updates: {{ mode: "external", keys: ["{pinned}"],
                 channel: "http://127.0.0.1:{forged}/releases.json" }}"#
        ),
    )
    .await;
    let c = client_on(ext.port).await.unwrap();
    let e = c
        .invoke_one(&node, "check_updates", args(&[]))
        .await
        .unwrap_err();
    assert!(e.message.contains("pinned release key"), "{}", e.message);
    assert_eq!(
        sys(ext.port, "update_available").await,
        Some(Value::Bool(false))
    );
    drop(c);
    ext.stop().await;

    // the default: off
    let off = Local::start("off", "").await;
    let c = client_on(off.port).await.unwrap();
    assert_eq!(
        sys_str(off.port, "update_mode").await.as_deref(),
        Some("off")
    );
    let e = c.invoke_one(&node, "update", go.clone()).await.unwrap_err();
    assert!(e.is(wyrm_core::Status::NotSupported), "{}", e.message);
    assert!(e.message.contains("\"off\""), "{}", e.message);
    drop(c);
    off.stop().await;

    // `self` with a binary that is not in the layout
    let bare = Local::start(
        "bare",
        &format!(r#"updates: {{ mode: "self", keys: ["{pinned}"] }}"#),
    )
    .await;
    let c = client_on(bare.port).await.unwrap();
    let e = c.invoke_one(&node, "update", go).await.unwrap_err();
    assert!(e.is(wyrm_core::Status::NotSupported), "{}", e.message);
    assert!(e.message.contains("install-layout"), "{}", e.message);
    let hint = sys_str(bare.port, "update_hint").await.unwrap();
    assert!(hint.contains("install-layout"), "{hint}");
    drop(c);
    bare.stop().await;
}

/// The release tooling (`wyrmd release …`) makes what a broker reads, and
/// signs nothing it did not check: `release index` adds to the published
/// index only when that index, every entry of it and the new release
/// verify, and when it holds every release that exists.
#[test]
fn release_index_refuses_what_does_not_verify() {
    use sha2::{Digest, Sha256};
    let d = temp_dir("tooling");
    let seed = hex::encode(RELEASE_SEED);
    let public = hex::encode(release_key().verifying_key().to_bytes());
    let other = ed25519_dalek::SigningKey::from_bytes(&[3; 32]);
    let tool = |args: &[&str], key: Option<&str>| {
        let mut c = Command::new(this_bin());
        c.arg("release").args(args).current_dir(&d).env_clear();
        if let Some(k) = key {
            c.env("WYRMD_RELEASE_KEY", k);
        }
        let out = c.output().unwrap();
        (
            out.status.success(),
            String::from_utf8_lossy(&out.stderr).into_owned()
                + String::from_utf8_lossy(&out.stdout).as_ref(),
        )
    };
    let ok = |args: &[&str], key: Option<&str>| {
        let (success, said) = tool(args, key);
        assert!(success, "{args:?}: {said}");
        said
    };
    let refused = |args: &[&str], want: &str| {
        let (success, said) = tool(args, None);
        assert!(!success, "{args:?} must be refused: {said}");
        assert!(said.contains(want), "{args:?}: {said}");
    };
    // what `release pack` leaves: an archive and what it is, for two versions
    let me = wyrmd::update::identity(None);
    let packed = |version: &str| {
        let dir = d.join(version);
        std::fs::create_dir_all(&dir).unwrap();
        let file = format!("wyrmd-{version}-{}.tar.gz", me.target);
        let bin = format!("the binary of {version}");
        let gz = testkit::tar_gz(&[testkit::tar_entry("wyrmd", b'0', 0o755, bin.as_bytes())]);
        std::fs::write(dir.join(&file), &gz).unwrap();
        let (sha256, size) = release::sha256_file(&dir.join(&file)).unwrap();
        let side = serde_json::json!({
            "identity": Identity { version: version.into(), ..me.clone() },
            "asset": Asset {
                file: file.clone(),
                sha256,
                size,
                url: String::new(),
                bin_sha256: hex::encode(Sha256::digest(bin.as_bytes())),
            },
        });
        std::fs::write(dir.join(format!("{file}.json")), side.to_string()).unwrap();
        (dir, file, format!("{version}/wyrmd-{version}.release.json"))
    };
    let (dir2, file2, r2) = packed("0.2.0");
    let (_, _, r3) = packed("0.3.0");
    // a description that is not of the archive beside it makes no document
    let side = dir2.join(format!("{file2}.json"));
    let good_side = std::fs::read_to_string(&side).unwrap();
    let hash = hex::encode(Sha256::digest(b"the binary of 0.2.0"));
    std::fs::write(&side, good_side.replace(&hash, &"0".repeat(64))).unwrap();
    refused(&["doc", "0.2.0"], "binary in the archive");
    std::fs::write(&side, &good_side).unwrap();
    ok(&["doc", "0.2.0", "--date", "2026-11-13"], None);
    ok(&["doc", "0.3.0", "--date", "2026-11-14"], None);

    // a release that is not signed, or signed by another key, starts no index
    let new = ["index", "--new", "--key", &public, &r2, "index.json"];
    refused(&new, "");
    ok(&["sign", &r2], Some(&"03".repeat(32)));
    refused(&new, "pinned release key");
    assert!(!d.join("index.json").exists());
    ok(&["sign", &r2], Some(&seed));
    ok(&["verify", &r2, "--key", &public], None);
    refused(&["verify", &r2], "no release key is pinned");
    // an index is started on purpose only
    refused(&["index", "--key", &public, &r2, "index.json"], "--new");
    let said = ok(&new, None);
    assert!(said.contains("sequence 1, 1 releases"), "{said}");
    refused(&new, "exists");
    // the channel file: only of an index that is signed
    let bundle = ["bundle", "index.json", "releases.json", "--key", &public];
    refused(&bundle, "index.json.sig");
    ok(&["sign", "--index", "index.json"], Some(&"03".repeat(32)));
    refused(&bundle, "pinned release key");
    ok(&["sign", "--index", "index.json"], Some(&seed));
    ok(&bundle, None);
    let said = ok(
        &["verify", "--channel", "releases.json", "--key", &public],
        None,
    );
    assert!(said.contains("sequence 1"), "{said}");
    let good = std::fs::read(d.join("releases.json")).unwrap();
    ok(&["sign", &r3], Some(&seed));

    // the next release is added to the published channel file only
    let add = |channel: &str, have: &str| {
        vec![
            "index".to_owned(),
            "--from".into(),
            channel.into(),
            "--key".into(),
            public.clone(),
            "--have".into(),
            have.into(),
            r3.clone(),
            "next.json".into(),
        ]
    };
    fn refs(v: &[String]) -> Vec<&str> {
        v.iter().map(String::as_str).collect()
    }
    let nothing_written = || assert!(!d.join("next.json").exists(), "next.json was written");
    // (1) an entry planted in it after it was signed
    let channel: release::Channel = serde_json::from_slice(&good).unwrap();
    let mut file: IndexFile = serde_json::from_str(&channel.index).unwrap();
    let evil = serde_json::to_string(&release_of(
        &Identity {
            version: "9.9.9".into(),
            ..me.clone()
        },
        Asset {
            file: format!("wyrmd-9.9.9-{}.tar.gz", me.target),
            sha256: "c".repeat(64),
            size: 1,
            url: String::new(),
            bin_sha256: "c".repeat(64),
        },
    ))
    .unwrap();
    file.releases.push(IndexEntry {
        signature: release::sign_release(evil.as_bytes(), &other),
        release: evil,
    });
    let planted = serde_json::to_vec(&file).unwrap();
    let write_channel = |name: &str, index: &[u8], signature: &str| {
        std::fs::write(d.join(name), release::bundle(index, signature).unwrap()).unwrap();
    };
    write_channel("planted.json", &planted, &channel.signature);
    refused(&refs(&add("planted.json", "0.2.0")), "not added to");
    nothing_written();
    // (2) signed as a whole by the real key all the same (a signer that
    // did not look): the planted entry still refuses it
    write_channel(
        "laundered.json",
        &planted,
        &release::sign_index(&planted, &release_key()),
    );
    refused(
        &refs(&add("laundered.json", "0.2.0")),
        "an entry is refused",
    );
    nothing_written();
    // (3) signed by another key
    write_channel(
        "foreign.json",
        channel.index.as_bytes(),
        &release::sign_index(channel.index.as_bytes(), &other),
    );
    refused(&refs(&add("foreign.json", "0.2.0")), "pinned release key");
    // (4) an old index put back: a version that was released is not in it
    refused(
        &refs(&add("releases.json", "0.2.5")),
        "older index was put back",
    );
    nothing_written();
    // (5) neither the published file nor --new
    refused(&["index", "--key", &public, &r3, "next.json"], "--new");

    // the published index takes the next release: one higher, to be signed
    let said = ok(&refs(&add("releases.json", "0.2.0")), None);
    assert!(said.contains("sequence 2, 2 releases"), "{said}");
    refused(
        &["bundle", "next.json", "releases.json", "--key", &public],
        "next.json.sig",
    );
    assert_eq!(std::fs::read(d.join("releases.json")).unwrap(), good);
    ok(&["sign", "--index", "next.json"], Some(&seed));
    ok(
        &["bundle", "next.json", "releases.json", "--key", &public],
        None,
    );
    // and a broker reads it
    let index = release::read_channel(
        &std::fs::read(d.join("releases.json")).unwrap(),
        &[release_key().verifying_key()],
    )
    .unwrap();
    assert_eq!(index.sequence, 2);
    assert_eq!(
        index.latest(&me.target).map(|s| s.release.version.as_str()),
        Some("0.3.0")
    );
    let _ = std::fs::remove_dir_all(&d);
}

/// The configuration is checked when it is read.
#[test]
fn the_updates_section_is_validated() {
    let parse = |updates: &str| {
        wyrmd::Config::from_json5(&format!(r#"{{ site: "s", updates: {{ {updates} }} }}"#))
            .map(|_| ())
            .map_err(|e| e.to_string())
    };
    assert!(parse("").is_ok());
    assert!(parse(r#"mode: "self""#).is_ok());
    assert!(parse(r#"mode: "auto""#)
        .unwrap_err()
        .contains("off, external or self"));
    assert!(parse(r#"mode: "external""#)
        .unwrap_err()
        .contains("updates.channel"));
    assert!(parse(r#"channel: "http://dl.example/releases.json""#)
        .unwrap_err()
        .contains("https://"));
    assert!(parse(r#"channel: "ftp://dl.example/releases.json""#).is_err());
    assert!(parse(r#"channel: "http://127.0.0.1.evil.example/releases.json""#).is_err());
    assert!(parse(r#"channel: "http://127.0.0.1@evil.example/releases.json""#).is_err());
    assert!(parse(r#"channel: "https://dl.example""#).is_err());
    assert!(parse(r#"channel: "http://127.0.0.1:8080/releases.json""#).is_ok());
    assert!(parse(r#"channel: "http://[::1]:8080/releases.json""#).is_ok());
    assert!(parse(r#"channel: "https://dl.example/releases.json""#).is_ok());
    assert!(parse(r#"channel: "https://dl.example:8443/a/releases.json""#).is_ok());
    // a channel holds no credential, and a refusal does not repeat one
    for (url, want) in [
        (
            "https://user:tok3n@dl.example/releases.json",
            "no name or password",
        ),
        (
            "https://tok3n@dl.example/releases.json",
            "no name or password",
        ),
        (
            "https://dl.example/releases.json?sig=tok3n",
            "no query string",
        ),
        ("https://dl.example/releases.json#tok3n", "no query string"),
        (
            "http://user:tok3n@127.0.0.1:8080/releases.json",
            "no name or password",
        ),
    ] {
        let e = parse(&format!(r#"channel: "{url}""#)).unwrap_err();
        assert!(e.contains(want), "{url}: {e}");
        assert!(!e.contains("tok3n") && !e.contains("user"), "{e}");
    }
    assert!(parse(r#"keys: ["abc"]"#).unwrap_err().contains("64 hex"));
    assert!(parse("trial_s: 5").unwrap_err().contains("10 to 3600"));
    assert!(parse("keep_days: 0").unwrap_err().contains("1 to 90"));
    assert!(parse("unknown: 1").is_err());
    // the guard is looked for before the start of the process, which
    // `wyrmd` notes first thing (a promoted standby opens its daemon later)
    let d = temp_dir("process-start");
    wyrmd::update::trial_start(&d, 30);
    let cfg = wyrmd::Config::from_json5(r#"{ site: "s" }"#).unwrap();
    let started = wyrmd::update::update_config(&cfg).unwrap().process_start;
    assert!(started.is_some_and(|t| t + 5 >= release::now_s()));
    let _ = std::fs::remove_dir_all(&d);
}
