use super::*;
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine as _;
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use wyrm_core::Quality;
use wyrm_history_sync::testkit::TcpHost;

fn cfg(port: u16, user: bool) -> Map {
    let mut m = Map::from([
        ("host".to_owned(), Value::from("127.0.0.1")),
        ("port".to_owned(), Value::UInt(port.into())),
        ("database".to_owned(), Value::from("plant")),
        ("tls".to_owned(), Value::Bool(false)),
    ]);
    if user {
        m.insert("user".into(), Value::from("wyrm"));
    }
    m
}

fn row(key: &str, t: u64, v: Value) -> Row {
    Row {
        seq: 1,
        site: "edge".into(),
        key: key.into(),
        t,
        v,
        q: Quality::Good,
    }
}

#[test]
fn params_are_checked() {
    assert!(Mongo::check(&cfg(27017, true)).is_ok());
    let with = |k: &str, v: Value| {
        let mut c = cfg(27017, true);
        c.insert(k.into(), v);
        Mongo::check(&c).unwrap_err()
    };
    assert!(with("oops", Value::UInt(1)).contains("oops"));
    assert!(with("host", Value::from("db.example.com")).contains("in the clear"));
    assert!(with("collection", Value::from("a.$b")).contains("collection"));
    assert!(with("database", Value::from("")).contains("database"));
    let mut c = cfg(27017, true);
    c.remove("tls");
    c.insert("host".into(), Value::from("cluster0.example.net"));
    assert!(Mongo::check(&c).is_ok(), "TLS by default");
}

#[test]
fn update_command_shape() {
    let rows = [
        row("wy/edge/p", 1_000, Value::Float(1.5)),
        row("wy/edge/p", 1_000, Value::Float(2.5)),
        row("wy/edge/s", 2_000, Value::from("x")),
        row("wy/edge/n", 3_000, Value::Null),
        row("wy/edge/u", 4_000, Value::UInt(u64::MAX)),
        row("wy/edge/m", 5_000, Value::Map(Map::new())),
    ];
    let cmd = update_command("plant", "h", &rows).unwrap();
    assert_eq!(get(&cmd, "update"), Some(&B::Str("h".into())));
    assert_eq!(get(&cmd, "ordered"), Some(&B::Bool(false)));
    assert_eq!(get(&cmd, "$db"), Some(&B::Str("plant".into())));
    let Some(B::Arr(updates)) = get(&cmd, "updates") else {
        panic!()
    };
    assert_eq!(
        updates.len(),
        4,
        "the last p, s, n and u; the map is left out"
    );
    let B::Doc(first) = &updates[0] else { panic!() };
    let id = B::Doc(doc([
        ("k", B::Str("wy/edge/p".into())),
        ("t", B::Int64(1000)),
    ]));
    assert_eq!(get(first, "q"), Some(&B::Doc(doc([("_id", id.clone())]))));
    assert_eq!(get(first, "upsert"), Some(&B::Bool(true)));
    let Some(B::Doc(u)) = get(first, "u") else {
        panic!()
    };
    assert_eq!(get(u, "_id"), Some(&id));
    assert_eq!(get(u, "value"), Some(&B::Double(2.5)));
    assert_eq!(get(u, "ts"), Some(&B::Date(1)));
    let B::Doc(big) = &updates[3] else { panic!() };
    let Some(B::Doc(u)) = get(big, "u") else {
        panic!()
    };
    assert_eq!(
        get(u, "value"),
        Some(&B::Double(u64::MAX as f64)),
        "past i64: a double"
    );
    assert_eq!(update_command("plant", "h", &rows[5..]), None);
}

type HmacSha256 = Hmac<Sha256>;

fn hmac(key: &[u8], data: &[u8]) -> Vec<u8> {
    let mut m = HmacSha256::new_from_slice(key).unwrap();
    m.update(data);
    m.finalize().into_bytes().to_vec()
}

/// The server's side of SCRAM-SHA-256 for `password`: (server-first, then the check of the
/// client-final that answers the server-final).
struct ScramServer {
    salted: Vec<u8>,
    first_bare: String,
    server_first: String,
}

impl ScramServer {
    fn first(password: &str, client_first: &str) -> Self {
        let bare = client_first.strip_prefix("n,,").unwrap().to_owned();
        let cnonce = bare.split(",r=").nth(1).unwrap().to_owned();
        let salt = b"saltsaltsalt";
        let iterations = 4096;
        // Hi() = PBKDF2-HMAC-SHA-256, one block
        let mut s = salt.to_vec();
        s.extend_from_slice(&1u32.to_be_bytes());
        let mut u = hmac(password.as_bytes(), &s);
        let mut salted = u.clone();
        for _ in 1..iterations {
            u = hmac(password.as_bytes(), &u);
            for (o, x) in salted.iter_mut().zip(&u) {
                *o ^= x;
            }
        }
        ScramServer {
            salted,
            first_bare: bare,
            server_first: format!("r={cnonce}SRV,s={},i={iterations}", B64.encode(salt)),
        }
    }

    /// `Some(server-final)` when the client's proof is right.
    fn last(&self, client_final: &str) -> Option<String> {
        let (without, proof) = client_final.rsplit_once(",p=")?;
        let auth = format!("{},{},{without}", self.first_bare, self.server_first);
        let client_key = hmac(&self.salted, b"Client Key");
        let stored = Sha256::digest(&client_key);
        let sig = hmac(&stored, auth.as_bytes());
        let key: Vec<u8> = B64
            .decode(proof)
            .ok()?
            .iter()
            .zip(sig)
            .map(|(a, b)| a ^ b)
            .collect();
        (Sha256::digest(&key) == stored).then(|| {
            let server_key = hmac(&self.salted, b"Server Key");
            format!("v={}", B64.encode(hmac(&server_key, auth.as_bytes())))
        })
    }
}

fn read_msg(s: &mut TcpStream) -> Option<(i32, Doc)> {
    let mut h = [0u8; 16];
    s.read_exact(&mut h).ok()?;
    let len = i32::from_le_bytes([h[0], h[1], h[2], h[3]]) as usize;
    let id = i32::from_le_bytes([h[4], h[5], h[6], h[7]]);
    let mut rest = vec![0u8; len - 16];
    s.read_exact(&mut rest).ok()?;
    Some((id, bson::read(&rest[5..]).ok()?))
}

fn reply(s: &mut TcpStream, to: i32, d: &Doc) {
    let body = bson::write(d);
    let len = 21 + body.len();
    let mut m = (len as i32).to_le_bytes().to_vec();
    m.extend_from_slice(&99i32.to_le_bytes());
    m.extend_from_slice(&to.to_le_bytes());
    m.extend_from_slice(&OP_MSG.to_le_bytes());
    m.extend_from_slice(&0u32.to_le_bytes());
    m.push(0);
    m.extend_from_slice(&body);
    s.write_all(&m).unwrap();
}

/// A MongoDB stand-in: SCRAM for "s3cret", then each command answered by the next of `script`
/// (`None` = `{ok: 1}`).
fn server(script: Vec<Option<Doc>>) -> (u16, Arc<Mutex<Vec<Doc>>>) {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    let got = Arc::new(Mutex::new(Vec::new()));
    let g = got.clone();
    std::thread::spawn(move || {
        let Ok((mut s, _)) = l.accept() else { return };
        let mut scram: Option<ScramServer> = None;
        let mut script = script.into_iter();
        while let Some((id, cmd)) = read_msg(&mut s) {
            g.lock().unwrap().push(cmd.clone());
            let ok = |extra: Vec<(&str, B)>| {
                let mut d = doc([("ok", B::Double(1.0))]);
                d.extend(extra.into_iter().map(|(k, v)| (k.to_owned(), v)));
                d
            };
            let answer = match cmd.first().map(|(k, _)| k.as_str()) {
                Some("saslStart") => {
                    let Some(B::Bin(p)) = get(&cmd, "payload") else {
                        return;
                    };
                    let sc = ScramServer::first("s3cret", &String::from_utf8_lossy(p));
                    let first = sc.server_first.clone().into_bytes();
                    scram = Some(sc);
                    ok(vec![
                        ("conversationId", B::Int32(1)),
                        ("payload", B::Bin(first)),
                        ("done", B::Bool(false)),
                    ])
                }
                Some("saslContinue") => {
                    let Some(B::Bin(p)) = get(&cmd, "payload") else {
                        return;
                    };
                    match scram
                        .as_ref()
                        .and_then(|sc| sc.last(&String::from_utf8_lossy(p)))
                    {
                        Some(fin) => ok(vec![
                            ("conversationId", B::Int32(1)),
                            ("payload", B::Bin(fin.into_bytes())),
                            ("done", B::Bool(true)),
                        ]),
                        None => doc([
                            ("ok", B::Double(0.0)),
                            ("code", B::Int32(18)),
                            ("errmsg", B::Str("Authentication failed.".into())),
                        ]),
                    }
                }
                _ => script.next().flatten().unwrap_or_else(|| ok(vec![])),
            };
            reply(&mut s, id, &answer);
        }
    });
    (port, got)
}

#[test]
fn logs_in_writes_and_classifies() {
    let write_error = doc([
        ("ok", B::Double(1.0)),
        (
            "writeErrors",
            B::Arr(vec![B::Doc(doc([
                ("index", B::Int32(0)),
                ("code", B::Int32(121)),
                ("errmsg", B::Str("Document failed validation".into())),
            ]))]),
        ),
    ]);
    let not_primary = doc([
        ("ok", B::Double(0.0)),
        ("code", B::Int32(10107)),
        ("errmsg", B::Str("not primary".into())),
    ]);
    let (port, got) = server(vec![None, None, Some(write_error), Some(not_primary)]);
    let mut h = TcpHost::default();
    let mut c = cfg(port, true);
    c.insert("ttl_days".into(), Value::UInt(30));
    let mut m = Mongo::connect(&mut h, &c, Some("s3cret")).unwrap();
    m.prepare(&mut h).unwrap();
    m.write(&mut h, &[row("wy/edge/p", 1, Value::Float(1.0))])
        .unwrap();
    let e = m
        .write(&mut h, &[row("wy/edge/p", 2, Value::Float(2.0))])
        .unwrap_err();
    assert!(
        matches!(e, TargetError::Fatal(_)) && e.message().contains("121"),
        "{e}"
    );
    let e = m.ping(&mut h).unwrap_err();
    assert!(matches!(e, TargetError::Reconnect(_)), "not primary: {e}");
    let got = got.lock().unwrap();
    let names: Vec<&str> = got.iter().map(|d| d[0].0.as_str()).collect();
    assert_eq!(
        names,
        [
            "saslStart",
            "saslContinue",
            "createIndexes",
            "update",
            "update",
            "ping"
        ]
    );
    let Some(B::Arr(idx)) = get(&got[2], "indexes") else {
        panic!()
    };
    let B::Doc(idx) = &idx[0] else { panic!() };
    assert_eq!(get(idx, "expireAfterSeconds"), Some(&B::Int64(30 * 86_400)));
    let Some(B::Bin(p)) = get(&got[0], "payload") else {
        panic!()
    };
    assert!(String::from_utf8_lossy(p).starts_with("n,,n=wyrm,r="));
}

#[test]
fn a_wrong_password_or_none_stops() {
    let (port, _) = server(vec![]);
    let mut h = TcpHost::default();
    let e = Mongo::connect(&mut h, &cfg(port, true), Some("wrong"))
        .err()
        .unwrap();
    assert!(
        matches!(e, TargetError::Fatal(_)) && e.message().contains("18"),
        "{e}"
    );
    // checked before any connection: port 1 is never tried
    let e = Mongo::connect(&mut h, &cfg(1, true), None).err().unwrap();
    assert!(
        matches!(e, TargetError::Fatal(_)) && e.message().contains("Set Password"),
        "{e}"
    );
    // no user: no login at all
    let (port, got) = server(vec![]);
    let mut m = Mongo::connect(&mut h, &cfg(port, false), None).unwrap();
    m.ping(&mut h).unwrap();
    assert_eq!(got.lock().unwrap().len(), 1, "ping only");
}

/// Review HS-1: data errors refuse the rows; the rest keeps its class.
#[test]
fn data_errors_refuse_rows() {
    assert!(matches!(class(10334, "m".into()), TargetError::Refused(_)));
    assert!(matches!(class(2, "m".into()), TargetError::Refused(_)));
    assert!(matches!(class(13, "m".into()), TargetError::Fatal(_)));
    assert!(matches!(class(91, "m".into()), TargetError::Reconnect(_)));
}
