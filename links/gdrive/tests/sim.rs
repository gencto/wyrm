//! The gdrive link against its simulator.

use rsa::pkcs1::EncodeRsaPublicKey;
use rsa::pkcs8::{EncodePrivateKey, LineEnding};
use std::sync::OnceLock;
use wyrm_core::Value;
use wyrm_filestore::testkit::{
    bootstrap, child, map, ok, refused, scenario, state, wait, Ext, H, SEED,
};
use wyrm_link_gdrive::sim::{self, Shared};
use wyrm_link_gdrive::GDriveStore;

/// A service account key made once per run: (PKCS#8 PEM, PKCS#1 public DER).
fn key() -> &'static (String, Vec<u8>) {
    static KEY: OnceLock<(String, Vec<u8>)> = OnceLock::new();
    KEY.get_or_init(|| {
        let k = rsa::RsaPrivateKey::new(&mut rsa::rand_core::OsRng, 2048).unwrap();
        let pem = k.to_pkcs8_pem(LineEnding::LF).unwrap().to_string();
        let public = k
            .to_public_key()
            .to_pkcs1_der()
            .unwrap()
            .as_bytes()
            .to_vec();
        (pem, public)
    })
}

fn key_json(email: &str) -> String {
    serde_json::json!({
        "type": "service_account",
        "client_email": email,
        "private_key": key().0,
        "token_uri": "https://oauth2.googleapis.com/token",
    })
    .to_string()
}

async fn setup(conn: &[(&str, Value)]) -> (H<GDriveStore>, Shared, tokio::task::JoinHandle<()>) {
    let (addr, st, task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut s = st.lock().unwrap();
        s.public_key = key().1.clone();
        s.refresh = Some(("cid".into(), "csecret".into(), "rtoken".into()));
        for (k, v) in SEED {
            s.put_path(k, v.as_bytes());
        }
    }
    let mut kv = vec![
        ("api_url", Value::Str(format!("http://{addr}"))),
        ("token_url", Value::Str(format!("http://{addr}/token"))),
        ("refresh_s", Value::Float(0.0)),
    ];
    kv.extend(conn.iter().cloned());
    (H::<GDriveStore>::start(bootstrap(map(&kv))).await, st, task)
}

fn ext(st: &Shared) -> impl Fn(Ext<'_>) + '_ {
    move |e| {
        let mut s = st.lock().unwrap();
        match e {
            Ext::Put(p, v) => {
                s.put_path(p, v);
            }
            Ext::Delete(p) => {
                if let Some(id) = s.find(p) {
                    s.files.remove(&id);
                }
            }
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn service_account_tree_folders_uploads() {
    let (h, st, _t) = setup(&[(
        "service_account_json",
        Value::Str(key_json("sim@wyrm.iam.gserviceaccount.com")),
    )])
    .await;
    st.lock().unwrap().page = 2;
    scenario(&h, &ext(&st)).await;
    // delete went to the trash
    {
        let s = st.lock().unwrap();
        assert!(s.files.values().any(|f| f.name == "top.txt" && f.trashed));
        assert!(s.seen.iter().any(|r| r == "POST /upload/drive/v3/files"));
    }
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn refresh_token_and_duplicate_names() {
    let (h, st, _t) = setup(&[
        ("auth", "refresh_token".into()),
        ("client_id", "cid".into()),
        ("client_secret", "csecret".into()),
        ("refresh_token", "rtoken".into()),
        ("trash", Value::Bool(false)),
    ])
    .await;
    {
        // Drive allows two files of one name, and `/` in names
        let mut s = st.lock().unwrap();
        let cfg = s.find("config").unwrap();
        s.add(&cfg, "plant.json", "application/json", b"second");
        s.add(&cfg, "a/b.txt", "text/plain", b"slash");
        s.add(
            &cfg,
            "Sheet",
            "application/vnd.google-apps.spreadsheet",
            b"",
        );
    }
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    // the files above may have come after the first read
    ok(&h, "c1", "refresh", map(&[])).await;
    wait("tree", 10, || {
        h.ctx().has_node("c1/files/config/plant.json")
    })
    .await;
    let (_, m) = h.meta("c1/files/config").await;
    let kids = m.unwrap().children.unwrap();
    assert_eq!(kids.len(), 4, "{kids:?}");
    assert!(child(&h, "c1/files/config", "a/b.txt").await.is_some());
    let (sheet, _) = child(&h, "c1/files/config", "Sheet").await.unwrap();
    let (a, _) = wyrm_filestore::testkit::act(&h, &sheet, "download", map(&[])).await;
    assert_eq!(
        wyrm_filestore::testkit::status(&a),
        wyrm_core::Status::InvalidParameter
    );
    // overwrite goes by the real name: `a_b.txt` is not `a/b.txt`, whose
    // path form it shares
    ok(
        &h,
        "c1/files/config",
        "upload",
        map(&[
            ("name", "a_b.txt".into()),
            ("text", "new".into()),
            ("overwrite", Value::Bool(true)),
        ]),
    )
    .await;
    {
        let s = st.lock().unwrap();
        let slash: Vec<_> = s.files.values().filter(|f| f.name == "a/b.txt").collect();
        assert_eq!(slash.len(), 1);
        assert_eq!(&slash[0].data[..], b"slash", "a/b.txt untouched");
        assert!(s
            .files
            .values()
            .any(|f| f.name == "a_b.txt" && &f.data[..] == b"new"));
    }
    assert!(child(&h, "c1/files/config", "a_b.txt").await.is_some());
    assert!(
        child(&h, "c1/files/config", "a/b.txt").await.is_some(),
        "both shown"
    );
    // delete for good
    let (f, _) = child(&h, "c1/files/config", "a/b.txt").await.unwrap();
    ok(&h, &f, "delete", map(&[])).await;
    assert!(!st
        .lock()
        .unwrap()
        .files
        .values()
        .any(|f| f.name == "a/b.txt"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn wrong_account_is_refused() {
    let (h, _st, _t) = setup(&[(
        "service_account_json",
        Value::Str(key_json("other@wyrm.iam.gserviceaccount.com")),
    )])
    .await;
    refused(&h).await;
    assert!(wyrm_filestore::testkit::error(&h, "c1")
        .unwrap()
        .contains("invalid_grant"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn bad_key_is_a_config_error() {
    let (h, _st, _t) =
        setup(&[("service_account_json", "{\"client_email\": \"a@b\"}".into())]).await;
    wait("failed", 10, || state(&h, "c1") == Some("failed")).await;
    let e = wyrm_filestore::testkit::error(&h, "c1").unwrap();
    assert!(e.contains("service_account_json"), "{e}");
    h.stop().await;
}

/// A file in parts: a resumable upload in chunks of 256 KiB.
#[tokio::test(flavor = "multi_thread")]
async fn large_files_in_parts() {
    let (h, st, _t) = setup(&[
        (
            "service_account_json",
            Value::Str(key_json("sim@wyrm.iam.gserviceaccount.com")),
        ),
        ("upload_chunk_kib", Value::UInt(256)),
    ])
    .await;
    wyrm_filestore::testkit::parts_scenario(&h, 3 * 1024 * 1024 + 5).await;
    assert!(
        st.lock().unwrap().sessions.is_empty(),
        "no session left open"
    );
    h.stop().await;
}

/// A file shrunk in Drive behind the tree: a part past its new end
/// answers no data, `eof`, and the size of Drive's 416.
#[tokio::test(flavor = "multi_thread")]
async fn a_part_past_the_end_answers_eof() {
    let (h, st, _t) = setup(&[(
        "service_account_json",
        Value::Str(key_json("sim@wyrm.iam.gserviceaccount.com")),
    )])
    .await;
    let node = "c1/files/reports/readme.txt";
    wait("tree", 10, || h.ctx().has_node(node)).await;
    {
        let mut s = st.lock().unwrap();
        let id = s.find("reports/readme.txt").expect("seeded");
        s.files.get_mut(&id).expect("file").data = b"abcd".to_vec().into();
    }
    let v = wyrm_filestore::testkit::ok(
        &h,
        node,
        "download_part",
        map(&[("offset", Value::UInt(8))]),
    )
    .await;
    let Some(Value::Map(m)) = v else {
        panic!("{v:?}")
    };
    assert_eq!(m["data"], Value::Bytes(Vec::new()));
    assert_eq!(m["eof"], Value::Bool(true));
    assert_eq!(m["size"], Value::UInt(4));
    h.stop().await;
}
